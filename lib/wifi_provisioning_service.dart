import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // debugPrint (satisfies the avoid_print lint)

/// Provisions the ESP32's Wi-Fi through the `esp-wifi-manager` captive-portal
/// HTTP API (see `components/esp-wifi-manager` in the firmware repo).
///
/// The phone joins the ESP32's setup access point, then talks to the portal
/// gateway at these endpoints:
///   * `status.json`  — is the portal alive / already provisioned?
///   * `ap.json`      — JSON array of visible networks (sorted by RSSI here)
///   * `connect.json` — SSID + password are sent in the `X-Custom-ssid` /
///     `X-Custom-pwd` headers (the JSON body is a timestamp placeholder the
///     portal ignores)
///
/// `Connection: close` on every request is mandatory: without it the
/// ESP32's sockets leak and the portal eventually refuses connections.
/// Provisions the ESP32's Wi-Fi while the device is in captive-portal AP mode.
///
/// Talks the raw esp-wifi-manager HTTP protocol directly (no discovery or
/// mDNS involved — the phone must be joined to the ESP32's own access point):
///   * `GET  /status.json` — reachability ping (200 = portal alive)
///   * `GET  /ap.json`     — Wi-Fi scan results, sorted by RSSI here
///   * `POST /connect.json` — sends SSID/password via `X-Custom-ssid` /
///     `X-Custom-pwd` headers with a JSON timestamp body
///
/// Every request sets `Connection: close` — the ESP32's HTTP server has a
/// tiny socket pool and wedges if connections linger.
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
      debugPrint("Connection Check Error: $e");
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
      debugPrint("AP Provisioning Error: $e");
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
        debugPrint("Raw ESP32 AP Response: ${response.body}"); 
        
        List<dynamic> networks = jsonDecode(response.body);
        networks.sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
        return networks;
      }
    } catch (e) {
      debugPrint("Failed to fetch networks: $e");
    }
    return [];
  }
}