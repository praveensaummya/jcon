import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Required for SecurityContext SSL context
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelayControlService {
  MqttServerClient? _mqttClient;

  // ==========================================
  // Relay Control (Hybrid: HTTP -> MQTT)
  // ==========================================

  /// Sends a relay command via local HTTP POST first, falling back to MQTT
  Future<Map<String, dynamic>> sendRelayCommand({
    required String payloadKey, // e.g., 'relay1_on', 'relay1_off'
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Fetch saved endpoint & topic configs
    final String ip = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
    final String port = prefs.getString('esp32_port') ?? '8080';
    final String cmdTopic = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';
    
    // 2. Fetch saved payload string, falling back to standard JSON format if unconfigured
    String payloadString = prefs.getString(payloadKey) ?? '';
    if (payloadString.isEmpty || payloadString == '{}') {
      payloadString = jsonEncode({"command": payloadKey});
    }

    // Attempt Local HTTP First (Defaults to path: '/api/relay')
    bool httpSuccess = await _sendLocalHttp(ip, port, payloadString);
    if (httpSuccess) {
      return {
        "success": true,
        "method": "HTTP (Local)",
        "message": "Command sent locally via HTTP: $payloadString"
      };
    }

    // Fallback to MQTT
    bool mqttSuccess = await _sendMqttMessage(cmdTopic, payloadString, prefs);
    if (mqttSuccess) {
      return {
        "success": true,
        "method": "MQTT (Cloud)",
        "message": "Command published via MQTT topic [$cmdTopic]: $payloadString"
      };
    }

    return {
      "success": false,
      "method": "FAILED",
      "message": "Failed to deliver command via local HTTP or MQTT."
    };
  }

  // ==========================================
  // Voice Control (Hybrid: HTTP -> MQTT)
  // ==========================================

  /// Fetches the current Voice Recognition ON/OFF state via HTTP GET
  Future<bool> getVoiceStatus(String ip, String port) async {
    try {
      String cleanIp = ip.trim().replaceAll('http://', '').replaceAll('https://', '');
      final url = Uri.parse('http://$cleanIp:$port/api/voice/status');
      
      final response = await http
          .get(url, headers: {'Connection': 'close'})
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['voice_enabled'] ?? true;
      }
    } catch (e) {
      print("Error fetching voice status: $e");
    }
    return true; // Default to true if unable to fetch
  }

  /// Sends a voice toggle command via local HTTP POST first, falling back to MQTT
  Future<Map<String, dynamic>> toggleVoiceRecognition(bool enable) async {
    final prefs = await SharedPreferences.getInstance();

    final String ip = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
    final String port = prefs.getString('esp32_port') ?? '8080';
    final String voiceCmdTopic = 'device/voice/command'; // MQTT topic for voice
    
    // Create the standard JSON payload
    final String payloadString = jsonEncode({"voice_enabled": enable});

    // Attempt Local HTTP First (Using the specific voice path)
    bool httpSuccess = await _sendLocalHttp(ip, port, payloadString, path: '/api/voice/config');
    if (httpSuccess) {
      return {
        "success": true,
        "method": "HTTP (Local)",
        "message": "Voice toggle sent locally via HTTP: $payloadString"
      };
    }

    // Fallback to MQTT
    bool mqttSuccess = await _sendMqttMessage(voiceCmdTopic, payloadString, prefs);
    if (mqttSuccess) {
      return {
        "success": true,
        "method": "MQTT (Cloud)",
        "message": "Voice toggle published via MQTT topic [$voiceCmdTopic]: $payloadString"
      };
    }

    return {
      "success": false,
      "method": "FAILED",
      "message": "Failed to deliver voice toggle command via local HTTP or MQTT."
    };
  }

  // ==========================================
  // Core Network Helpers
  // ==========================================

  /// Sends local HTTP POST with connection cleanup and variable path routing
  Future<bool> _sendLocalHttp(String ip, String port, String jsonPayload, {String path = '/api/relay'}) async {
    try {
      String cleanIp = ip.trim().replaceAll('http://', '').replaceAll('https://', '');
      final url = Uri.parse('http://$cleanIp:$port$path');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'close', // Critical: prevents ESP32 socket leak (Error 23)
            },
            body: jsonPayload,
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      print("Local HTTP failed/timed out for $path: $e");
      return false;
    }
  }

  /// Publishes message to MQTT Cloud Broker
  Future<bool> _sendMqttMessage(String topic, String jsonPayload, SharedPreferences prefs) async {
    try {
      // Synchronized with MqttHttpConfigScreen keys ('mqtt_uri' / 'broker_uri')
      final String broker = prefs.getString('mqtt_uri') ?? prefs.getString('broker_uri') ?? '';
      final String user = prefs.getString('mqtt_user') ?? prefs.getString('broker_user') ?? '';
      final String pass = prefs.getString('mqtt_pass') ?? prefs.getString('broker_pass') ?? '';

      if (broker.isEmpty) {
        print("MQTT Error: Broker URI is empty.");
        return false;
      }

      String cleanBroker = broker
          .replaceAll('mqtts://', '')
          .replaceAll('mqtt://', '')
          .split('/')[0]
          .split(':')[0];

      _mqttClient = MqttServerClient.withPort(
        cleanBroker, 
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}', 
        8883,
      );
      _mqttClient!.secure = true;
      _mqttClient!.securityContext = SecurityContext.defaultContext; // Handshake validation
      _mqttClient!.logging(on: false);
      _mqttClient!.keepAlivePeriod = 20;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
          .startClean();
      _mqttClient!.connectionMessage = connMessage;

      await _mqttClient!.connect(user, pass);

      if (_mqttClient!.connectionStatus?.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(jsonPayload);
        _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        
        // Short delay to flush socket connection cleanly
        await Future.delayed(const Duration(milliseconds: 300));
        _mqttClient!.disconnect();
        return true;
      }
    } catch (e) {
      print("MQTT Publish Error: $e");
      _mqttClient?.disconnect();
    }
    return false;
  }
}