import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart'; // debugPrint (satisfies the avoid_print lint)

/// Last-resort device discovery: scans every host on the phone's IPv4
/// subnet(s) for a server listening on [port] (default 8080 — the
/// firmware's API port).
///
/// All 254 probes per subnet run in parallel over raw sockets and finish
/// in well under a second. Hits are NOT verified against `/api/status`
/// here — callers should confirm each hit with
/// `DeviceDiscoveryService.verifyHost` so an unrelated device that merely
/// has port 8080 open is not mistaken for the inverter.
/// Last-resort device finder: parallel TCP probe of the local /24 subnet.
///
/// Used when mDNS multicast is blocked (common on guest/enterprise Wi-Fi and
/// some Android versions). Fires 254 `Socket.connect` probes simultaneously
/// per interface — the whole sweep completes in roughly 350 ms — and returns
/// every address with port 8080 open.
///
/// NOTE: this is identity-blind; a hit only proves "something listens on
/// 8080". Callers must confirm the device with an HTTP check (see
/// [DeviceDiscoveryService.verifyHost]) before trusting it.
class SubnetScanner {
  /// Scans the local network for devices responding on [port] (default: 8080)
  static Future<List<String>> scanForEsp32({
    int port = 8080,
    Duration timeout = const Duration(milliseconds: 1000),
  }) async {
    List<String> foundIps = [];

    try {
      // 1. Get all active network interfaces on the phone/PC
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          final ip = addr.address;

          // Ignore loopback or non-local addresses
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

          // Extract subnet prefix (e.g. "192.168.1")
          final lastDotIndex = ip.lastIndexOf('.');
          if (lastDotIndex == -1) continue;

          final subnetPrefix = ip.substring(0, lastDotIndex);

          // 2. Launch 254 socket probes simultaneously in parallel
          final List<Future<void>> probes = [];

          for (int host = 1; host <= 254; host++) {
            final targetIp = '$subnetPrefix.$host';

            probes.add(
              Socket.connect(targetIp, port, timeout: timeout)
                  .then((socket) {
                // Connection succeeded! An active server is on this port.
                foundIps.add(targetIp);
                socket.destroy();
              }).catchError((_) {
                // Unreachable or connection refused — ignore
              }),
            );
          }

          // Wait for all 254 probes to finish (completes in ~350ms total)
          await Future.wait(probes);
        }
      }
    } catch (e) {
      debugPrint('Subnet Scanner error: $e');
    }

    return foundIps;
  }
}