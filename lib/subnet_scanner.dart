import 'dart:io';
import 'dart:async';

class SubnetScanner {
  /// Scans the local network for devices responding on [port] (default: 8080)
  static Future<List<String>> scanForEsp32({
    int port = 8080,
    Duration timeout = const Duration(milliseconds: 350),
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
      print('Subnet Scanner error: $e');
    }

    return foundIps;
  }
}