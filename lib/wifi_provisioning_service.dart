import 'dart:convert';
import 'package:http/http.dart' as http;

class WifiProvisioningService {
  
  // NEW: Pings the ESP32 to verify we are connected to it
  Future<bool> checkConnection(String ipAddress) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ipAddress/status.json'))
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
        Uri.parse('http://$ipAddress/connect.json'),
        headers: {
          "Content-Type": "application/json",
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

  // Note: Corrected spelling to getAvailableNetworks
  Future<List<dynamic>> getAvailableNetworks(String ipAddress) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ipAddress/ap.json'))
          .timeout(const Duration(seconds: 8)); // Increased timeout to give ESP32 time to scan

      if (response.statusCode == 200) {
        // Print the raw response to the debug console to see what the ESP32 actually returns!
        print("Raw ESP32 AP Response: ${response.body}"); 
        
        List<dynamic> networks = jsonDecode(response.body);
        networks.sort((a, b) => b['rssi'].compareTo(a['rssi']));
        return networks;
      }
    } catch (e) {
      print("Failed to fetch networks: $e");
    }
    return [];
  }
}