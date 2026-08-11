import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelayControlService {
  MqttServerClient? _mqttClient;

  /// Sends a relay command via local HTTP POST first, falling back to MQTT
  Future<Map<String, dynamic>> sendRelayCommand({
    required String payloadKey, // e.g., 'relay1_on', 'relay1_off'
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Fetch saved endpoint & topic configs
    final String ip = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
    final String port = prefs.getString('esp32_port') ?? '8080';
    final String cmdTopic = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';
    
    // 2. Fetch saved payload JSON string
    final String payloadString = prefs.getString(payloadKey) ?? '{}';

    // Attempt Local HTTP First
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

  /// Sends local HTTP POST with connection cleanup
  Future<bool> _sendLocalHttp(String ip, String port, String jsonPayload) async {
    try {
      String cleanIp = ip.trim().replaceAll('http://', '').replaceAll('https://', '');
      final url = Uri.parse('http://$cleanIp:$port/api/relay');

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
      print("Local HTTP failed/timed out: $e");
      return false;
    }
  }

  /// Publishes message to MQTT Cloud Broker
  Future<bool> _sendMqttMessage(String topic, String jsonPayload, SharedPreferences prefs) async {
    try {
      final String broker = prefs.getString('broker_uri') ?? '';
      final String user = prefs.getString('broker_user') ?? '';
      final String pass = prefs.getString('broker_pass') ?? '';

      if (broker.isEmpty) return false;

      String cleanBroker = broker
          .replaceAll('mqtts://', '')
          .replaceAll('mqtt://', '')
          .split(':')
          .first;

      _mqttClient = MqttServerClient.withPort(cleanBroker, 'flutter_client_${DateTime.now().millisecondsSinceEpoch}', 8883);
      _mqttClient!.secure = true;
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
        
        // Short delay to flush connection cleanly
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