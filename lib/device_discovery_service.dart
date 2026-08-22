import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central device discovery for the ESP32-S3 Inverter.
///
/// Resolution order (fastest first):
///   1. Cached resolved IP (SharedPreferences: `esp32_resolved_ip`) - verified live
///   2. Real mDNS lookup via `multicast_dns` package ("esp32-inverter.local")
///   3. OS-level ".local" hostname HTTP probe (fallback, works on iOS/most desktops)
///
/// Every candidate is verified with an HTTP 200 from GET /api/status before
/// being accepted, so we never cache a wrong device that merely has port 8080 open.
class DeviceDiscoveryService {
  /// mDNS host advertised by the firmware (mdns_hostname_set in main.c)
  static const String mdnsHostName = 'esp32-inverter.local';
  static const int devicePort = 8080;
  static const String defaultDeviceHost = mdnsHostName;

  static const String _resolvedIpKey = 'esp32_resolved_ip';

  /// Returns the best reachable host for HTTP calls:
  /// a verified raw IP if possible, otherwise the ".local" hostname fallback,
  /// or null when the device cannot be found anywhere.
  static Future<String?> resolveDeviceIp({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // --- 1. Cached IP: cheapest path, verify it is still the right device ---
    final cached = prefs.getString(_resolvedIpKey);
    if (cached != null && cached.isNotEmpty) {
      if (await verifyHost(cached)) {
        return cached;
      }
      // Stale IP (DHCP changed / device moved on) - drop it and rediscover.
      await prefs.remove(_resolvedIpKey);
    }

    // --- 2. Proper mDNS resolution (works reliably on Android & iOS) ---
    try {
      final ip = await lookupMdnsAddress().timeout(timeout);
      if (ip != null && await verifyHost(ip)) {
        await prefs.setString(_resolvedIpKey, ip);
        return ip;
      }
    } catch (_) {
      // mDNS unavailable / timed out - fall through
    }

    // --- 3. OS-level ".local" fallback (older behaviour, kept for compatibility).
    //        Some platforms (notably many Android versions) can't resolve .local
    //        natively, which is why step 2 above exists.
    if (await verifyHost(mdnsHostName)) {
      return mdnsHostName;
    }

    return null;
  }

  /// Performs a true multicast DNS lookup of [mdnsHostName] and returns its
  /// IPv4 address, or null when not found.
  static Future<String?> lookupMdnsAddress({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final client = MDnsClient();
    try {
      await client.start();
      // The lookup stream ends automatically after [timeout] if nothing answers.
      await for (final IPAddressResourceRecord record
          in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(mdnsHostName),
        timeout: timeout,
      )) {
        final String ip = record.address.address;
        if (ip.isNotEmpty && !ip.startsWith('127.')) {
          return ip;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.stop();
    }
  }

  /// True when [host] (IP or .local name) answers GET /api/status with HTTP 200.
  static Future<bool> verifyHost(String host, {int port = devicePort}) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://$host:$port/api/status'),
            headers: {'Connection': 'close'},
          )
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
