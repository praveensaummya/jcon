import 'dart:convert';
import 'package:http/http.dart' as http;

class WifiProvisioningService {
  
  /// Formats the target IP URL cleanly (handles port if included)
  String _formatUrl(String ipAddress, String endpoint) {
    String cleanIp = ipAddress.trim().replaceAll('http://', '').replaceAll('https://', '');
    return 'http://$cleanIp/$endpoint';
  }

  // Pings the ESP32 to verify connection
  Future<bool> checkConnection(String ipAddress) async {
    try {
      final response = await http
          .get(
            Uri.parse(_formatUrl(ipAddress, 'status.json')),
            headers: {'Connection': 'close'}, // Prevents ESP32 socket leak
          )
          .timeout(const Duration(seconds: 3));
      
      return response.statusCode == 200;
    } catch (e) {
      print("Connection Check Error: $e");
      return false;
    }
  }

  Future<bool> sendWifiCredentials(String ipAddress, String ssid, String password) async {
    try {
      final response = await http.post(
        Uri.parse(_formatUrl(ipAddress, 'connect.json')),
        headers: {
          "Content-Type": "application/json",
          "Connection": "close", // Prevents ESP32 socket leak
          "X-Custom-ssid": ssid,
          "X-Custom-pwd": password,
        },
        body: jsonEncode({"timestamp": DateTime.now().millisecondsSinceEpoch}),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print("AP Provisioning Error: $e");
      return false;
    }
  }

  Future<List<dynamic>> getAvailableNetworks(String ipAddress) async {
    try {
      final response = await http
          .get(
            Uri.parse(_formatUrl(ipAddress, 'ap.json')),
            headers: {'Connection': 'close'}, // Prevents ESP32 socket leak
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        print("Raw ESP32 AP Response: ${response.body}"); 
        
        List<dynamic> networks = jsonDecode(response.body);
        networks.sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
        return networks;
      }
    } catch (e) {
      print("Failed to fetch networks: $e");
    }
    return [];
  }
}