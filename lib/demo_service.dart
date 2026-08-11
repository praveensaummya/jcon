import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DemoService {
  // MASTER DEMO SWITCH:
  // Set to `true`  -> Demo Mode with 20-minute countdown lock.
  // Set to `false` -> Full Original Version with unlimited access.
  static const bool isDemoEnabled = false;
  static const int demoDurationMinutes = 120;
  static const String _keyStartTime = 'demo_start_utc_ms';

  /// Fetches global UTC time from public time API
  static Future<DateTime?> fetchGlobalUtcTime() async {
    try {
      final response = await http
          .get(Uri.parse('http://worldtimeapi.org/api/ip'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['utc_datetime']);
      }
    } catch (_) {
      // Fallback API if worldtimeapi fails
      try {
        final fallbackResponse = await http
            .get(Uri.parse('https://timeapi.io/api/time/current/zone?timeZone=UTC'))
            .timeout(const Duration(seconds: 5));

        if (fallbackResponse.statusCode == 200) {
          final data = jsonDecode(fallbackResponse.body);
          return DateTime.parse(data['dateTime']);
        }
      } catch (_) {}
    }
    return null; // Return null if offline / unable to verify internet time
  }

  /// Checks remaining demo time in seconds.
  /// Returns -1 if offline (cannot verify global time).
  /// Returns 0 if demo is expired.
  static Future<int> getRemainingSeconds() async {
    if (!isDemoEnabled) return 999999;
    final globalTime = await fetchGlobalUtcTime();
    if (globalTime == null) {
      return -1; // Internet verification failed
    }

    final prefs = await SharedPreferences.getInstance();
    int? startMs = prefs.getInt(_keyStartTime);

    // First time launching the app: save current global UTC timestamp
    if (startMs == null) {
      startMs = globalTime.millisecondsSinceEpoch;
      await prefs.setInt(_keyStartTime, startMs);
    }

    final startTime = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    final expiryTime = startTime.add(const Duration(minutes: demoDurationMinutes));

    final remainingMs = expiryTime.difference(globalTime).inMilliseconds;

    if (remainingMs <= 0) {
      return 0; // Expired
    }

    return (remainingMs / 1000).ceil();
  }
}