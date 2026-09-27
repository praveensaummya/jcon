import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Time-locked demo mode.
///
/// [isDemoEnabled] is the master switch: `false` ships the full,
/// unrestricted app. When `true`, the first-launch timestamp is stored in
/// SharedPreferences (`demo_start_utc_ms`) and [getRemainingSeconds]
/// counts down a [demoDurationMinutes]-minute trial. The countdown uses a
/// globally verified UTC time (worldtimeapi, with a fallback API), so
/// clearing app data or rewinding the phone clock cannot extend the trial;
/// when the time can't be verified the caller gets `-1`.
/// Optional 20-minute demo countdown, verified against public UTC time APIs.
///
/// The countdown deliberately uses INTERNET time (worldtimeapi.org with a
/// timeapi.io fallback) instead of the device clock, so clearing app storage
/// or changing the phone's clock cannot reset the trial.
///
/// Compile-time switch [isDemoEnabled] gates everything: when `false` the
/// app is the full unlimited version and [getRemainingSeconds] always
/// reports a large positive number, so UI countdown code can stay in place.
///
/// Return contract of [getRemainingSeconds]:
///   * `> 0`  — seconds remaining (large value when demo mode is off)
///   * `0`    — demo expired
///   * `-1`   — offline: UTC time could not be verified, so the demo
///              cannot be trusted to still be running
class DemoService {
  // MASTER DEMO SWITCH:
  // Set to `true`  -> Demo Mode with 20-minute countdown lock.
  // Set to `false` -> Full Original Version with unlimited access.
  static const bool isDemoEnabled = false;
  static const int demoDurationMinutes = 20;
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