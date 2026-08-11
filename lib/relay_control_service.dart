import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Required for SecurityContext SSL context
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelayControlService {
  MqttServerClient? _mqttClient;

  // 🛡️ Global Mutex Lock: Prevents overlapping network calls
  static bool _isExecutingCommand = false;

  // ==========================================
  // Relay Control (Hybrid / Direct HTTP / Direct MQTT)
  // ==========================================

  /// Sends a relay command based on user preference ('auto', 'http', 'mqtt')
  Future<Map<String, dynamic>> sendRelayCommand({
    required String payloadKey, // e.g., 'relay1_on', 'relay1_off'
  }) async {
    if (_isExecutingCommand) {
      return {
        "success": false,
        "method": "REJECTED",
        "message": "A command is already processing. Please wait..."
      };
    }

    _isExecutingCommand = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final String ip = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      final String port = prefs.getString('esp32_port') ?? '8080';
      final String cmdTopic = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';
      final String commMode = prefs.getString('comm_mode') ?? 'auto';
      
      final Map<String, String> defaultPayloads = {
        'relay1_on': '{"relay": 1, "state": 1}',
        'relay1_off': '{"relay": 1, "state": 0}',
        'relay2_on': '{"relay": 2, "state": 1}',
        'relay2_off': '{"relay": 2, "state": 0}',
      };

      String payloadString = prefs.getString(payloadKey) ?? '';
      if (payloadString.trim().isEmpty || payloadString == '{}') {
        payloadString = defaultPayloads[payloadKey] ?? jsonEncode({"command": payloadKey});
      }

      // MODE 1: DIRECT CLOUD MQTT ONLY
      if (commMode == 'mqtt') {
        bool mqttSuccess = await _sendMqttMessage(cmdTopic, payloadString, prefs);
        if (mqttSuccess) {
          return {
            "success": true,
            "method": "MQTT (Direct)",
            "message": "Instant command sent via Cloud MQTT: $payloadString"
          };
        }
        return {
          "success": false,
          "method": "FAILED",
          "message": "MQTT command failed. Check broker settings."
        };
      }

      // MODE 2: LOCAL HTTP FIRST
      bool httpSuccess = await _sendLocalHttp(ip, port, payloadString, path: '/api/relay');
      if (httpSuccess) {
        return {
          "success": true,
          "method": "HTTP (Local)",
          "message": "Command sent locally via HTTP: $payloadString"
        };
      }

      if (commMode == 'http') {
        return {
          "success": false,
          "method": "FAILED",
          "message": "Local HTTP request failed (Local HTTP Only mode active)."
        };
      }

      // MODE 3: AUTO MODE FALLBACK TO MQTT
      bool mqttSuccess = await _sendMqttMessage(cmdTopic, payloadString, prefs);
      if (mqttSuccess) {
        return {
          "success": true,
          "method": "MQTT (Fallback)",
          "message": "Command published via MQTT topic [$cmdTopic]: $payloadString"
        };
      }

      return {
        "success": false,
        "method": "FAILED",
        "message": "Failed to deliver command via local HTTP or MQTT."
      };
    } finally {
      _isExecutingCommand = false;
    }
  }

  // ==========================================
  // Voice Control (Hybrid / Direct HTTP / Direct MQTT)
  // ==========================================

  /// Fetches the current Voice Recognition ON/OFF state via HTTP GET
  Future<bool> getVoiceStatus(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    final String commMode = prefs.getString('comm_mode') ?? 'auto';

    if (commMode == 'mqtt') {
      return true;
    }

    try {
      String cleanIp = ip.trim().replaceAll('http://', '').replaceAll('https://', '');
      final url = Uri.parse('http://$cleanIp:$port/api/voice/status');
      
      final response = await http
          .get(url, headers: {'Connection': 'close'})
          .timeout(const Duration(seconds: 2));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return data['voice_enabled'] ?? data['enabled'] ?? true;
      }
    } catch (e) {
      print("[VOICE STATUS ERROR] $e");
    }
    return true; 
  }

  /// Sends a voice toggle command based on preferred communication mode
  Future<Map<String, dynamic>> toggleVoiceRecognition(bool enable) async {
    if (_isExecutingCommand) {
      return {
        "success": false,
        "method": "REJECTED",
        "message": "A command is currently processing. Try again in a moment."
      };
    }

    _isExecutingCommand = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final String ip = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      final String port = prefs.getString('esp32_port') ?? '8080';
      final String voiceCmdTopic = prefs.getString('mqtt_voice_topic') ?? 'device/voice/command';
      final String commMode = prefs.getString('comm_mode') ?? 'auto';
      
      // Look for stored voice payload preferences or fallback to standard JSON
      final String customVoiceKey = enable ? 'voice_on_payload' : 'voice_off_payload';
      String payloadString = prefs.getString(customVoiceKey) ?? '';
      
      if (payloadString.trim().isEmpty || payloadString == '{}') {
        payloadString = jsonEncode({"voice_enabled": enable, "enabled": enable});
      }

      // MODE 1: DIRECT CLOUD MQTT ONLY
      if (commMode == 'mqtt') {
        bool mqttSuccess = await _sendMqttMessage(voiceCmdTopic, payloadString, prefs);
        if (mqttSuccess) {
          return {
            "success": true,
            "method": "MQTT (Direct)",
            "message": "Voice toggle sent instantly via MQTT: $payloadString"
          };
        }
        return {
          "success": false,
          "method": "FAILED",
          "message": "Failed to send Voice command via MQTT."
        };
      }

      // MODE 2: LOCAL HTTP FIRST
      bool httpSuccess = await _sendLocalHttp(ip, port, payloadString, path: '/api/voice/config');
      
      // Fallback: Try alternative voice endpoint path if primary path fails
      if (!httpSuccess && commMode != 'mqtt') {
        httpSuccess = await _sendLocalHttp(ip, port, payloadString, path: '/api/voice');
      }

      if (httpSuccess) {
        return {
          "success": true,
          "method": "HTTP (Local)",
          "message": "Voice toggle sent locally via HTTP: $payloadString"
        };
      }

      // Stop if strictly in 'http' mode
      if (commMode == 'http') {
        return {
          "success": false,
          "method": "FAILED",
          "message": "Voice toggle failed via Local HTTP (check ESP32 IP address or endpoint)."
        };
      }

      // MODE 3: AUTO MODE FALLBACK TO MQTT
      bool mqttSuccess = await _sendMqttMessage(voiceCmdTopic, payloadString, prefs);
      if (mqttSuccess) {
        return {
          "success": true,
          "method": "MQTT (Fallback)",
          "message": "Voice toggle published via MQTT topic [$voiceCmdTopic]: $payloadString"
        };
      }

      return {
        "success": false,
        "method": "FAILED",
        "message": "Failed to deliver voice toggle command via local HTTP or MQTT."
      };
    } finally {
      _isExecutingCommand = false;
    }
  }

  // ==========================================
  // Core Network Helpers
  // ==========================================

  /// Sends local HTTP POST with connection cleanup and flexible status code validation
  Future<bool> _sendLocalHttp(String ip, String port, String jsonPayload, {String path = '/api/relay'}) async {
    try {
      String cleanIp = ip.trim().replaceAll('http://', '').replaceAll('https://', '');
      final url = Uri.parse('http://$cleanIp:$port$path');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'close', // Prevents socket exhaustion on ESP32
            },
            body: jsonPayload,
          )
          .timeout(const Duration(seconds: 3));

      // Accepts 200 OK, 201 Created, or 204 No Content as valid success states
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      } else {
        print("[HTTP ERROR] Path $path returned status code ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("[HTTP EXCEPTION] Failed connecting to $path: $e");
      return false;
    }
  }

  /// Publishes message to MQTT Cloud Broker using persistent socket reuse
  Future<bool> _sendMqttMessage(String topic, String jsonPayload, SharedPreferences prefs) async {
    try {
      final String broker = prefs.getString('mqtt_uri') ?? prefs.getString('broker_uri') ?? '';
      final String user = prefs.getString('mqtt_user') ?? prefs.getString('broker_user') ?? '';
      final String pass = prefs.getString('mqtt_pass') ?? prefs.getString('broker_pass') ?? '';

      if (broker.isEmpty) {
        print("MQTT Error: Broker URI is empty.");
        return false;
      }

      if (_mqttClient == null || _mqttClient!.connectionStatus?.state != MqttConnectionState.connected) {
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
        _mqttClient!.securityContext = SecurityContext.defaultContext;
        _mqttClient!.logging(on: false);
        _mqttClient!.keepAlivePeriod = 20;

        final connMessage = MqttConnectMessage()
            .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
            .startClean();
        _mqttClient!.connectionMessage = connMessage;

        await _mqttClient!.connect(user, pass);
      }

      if (_mqttClient!.connectionStatus?.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(jsonPayload);
        _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        return true;
      }
    } catch (e) {
      print("MQTT Publish Error: $e");
      _mqttClient?.disconnect();
      _mqttClient = null;
    }
    return false;
  }

  /// Disconnects active MQTT client connection
  void dispose() {
    _mqttClient?.disconnect();
    _mqttClient = null;
  }
}