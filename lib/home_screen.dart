import 'dart:async'; // Required for Timer
// Required for Set
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Required for ScrollController
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// --- Existing Services ---
import 'add_device_screen.dart';
import 'relay_control_service.dart';
import 'device_discovery_service.dart'; // mDNS + .local + cached-IP discovery
import 'subnet_scanner.dart'; // Direct Subnet IP Scanner Integration

/// Main dashboard.
///
/// Shows device reachability (via `GET /api/status`), one card per relay
/// with live state, the voice-recognition toggle (`/api/voice/*`) and a
/// terminal-style log of every command result. Targets and preferences
/// are loaded from SharedPreferences (keys documented in the config
/// screens).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Service Integration
  final RelayControlService _controlService = RelayControlService();

  // Device Network Target & Comm Mode
  String deviceIp = "esp32-inverter.local";
  String devicePort = "8080";
  String commMode = "auto"; // 'auto', 'http', or 'mqtt'

  // Reachability & Connection State
  bool _isCheckingConnection = false;
  bool _isDeviceConnected = false;

  // Voice Recognition State
  bool _voiceEnabled = true;
  bool _isVoiceLoading = false;

  // Relay State & Config
  String relay1Name = "Relay 1";
  bool relay1State = false;

  String relay2Name = "Relay 2";
  bool relay2State = false;

  // Anti-Spam Relay Processing Lock Tracker
  final Set<int> _busyRelays = {};

  // Terminal Log Output & Controller
  final List<String> cmdLogs = [
    "System Initialized.",
    "Ready for local HTTP or MQTT fallback commands...",
  ];
  final ScrollController _terminalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDeviceConfiguration();
  }

  @override
  void dispose() {
    _terminalScrollController.dispose();
    super.dispose();
  }

  // Load target IP, port, comm mode, and relay names from SharedPreferences
  Future<void> _loadDeviceConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      deviceIp = prefs.getString('esp32_ip') ?? 'esp32-inverter.local';
      devicePort = prefs.getString('esp32_port') ?? '8080';
      commMode = prefs.getString('comm_mode') ?? 'auto';

      relay1Name = prefs.getString('relay1_name') ?? 'Relay 1';
      relay2Name = prefs.getString('relay2_name') ?? 'Relay 2';
    });

    await _checkDeviceReachability();
  }

  // Cycle through comm modes: AUTO -> HTTP -> MQTT -> AUTO
  Future<void> _cycleCommMode() async {
    String nextMode;
    if (commMode == 'auto') {
      nextMode = 'http';
    } else if (commMode == 'http') {
      nextMode = 'mqtt';
    } else {
      nextMode = 'auto';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('comm_mode', nextMode);

    setState(() {
      commMode = nextMode;
    });

    _addLog(
      "[MODE SWITCH] Communication mode set to: ${nextMode.toUpperCase()}",
    );
  }

  Color _getModeColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'http':
        return Colors.orange[800]!;
      case 'mqtt':
        return Colors.purple;
      case 'auto':
      default:
        return Colors.blueAccent;
    }
  }

  IconData _getModeIcon(String mode) {
    switch (mode.toLowerCase()) {
      case 'http':
        return Icons.wifi;
      case 'mqtt':
        return Icons.cloud_outlined;
      case 'auto':
      default:
        return Icons.sync_alt_rounded;
    }
  }

  Future<void> _checkDeviceReachability() async {
    if (_isCheckingConnection) return;

    setState(() {
      _isCheckingConnection = true;
    });

    _addLog("[INFO] Verifying device at $deviceIp:$devicePort...");

    final targetPort = int.tryParse(devicePort) ?? 8080;
    bool isReachable = false;

    // --- TIER 1: Direct HTTP to the configured host (.local name or IP) ---
    try {
      final pingUri = Uri.parse('http://$deviceIp:$targetPort/api/status');
      final response = await http
          .get(pingUri)
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        isReachable = true;
      }
    } catch (_) {
      isReachable = false;
    }

    // --- TIER 2: Real mDNS resolution (multicast_dns) -> verified raw IP ---
    // Android often can't resolve ".local" natively, so we resolve it ourselves.
    if (!isReachable) {
      try {
        final resolvedIp = await DeviceDiscoveryService.resolveDeviceIp();
        if (resolvedIp != null) {
          final response = await http
              .get(Uri.parse('http://$resolvedIp:$targetPort/api/status'))
              .timeout(const Duration(seconds: 2));

          if (response.statusCode == 200) {
            isReachable = true;

            // Remember the working IP so future checks & commands skip discovery
            if (resolvedIp != deviceIp) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('esp32_ip', resolvedIp);
              setState(() {
                deviceIp = resolvedIp;
              });
              _addLog("[INFO] Discovered device via mDNS at $resolvedIp");
            }
          }
        }
      } catch (_) {
        isReachable = false;
      }
    }

    // --- TIER 3: Subnet scan fallback (last resort) ---
    // FIX: previously this compared scanned raw IPs against a ".local" hostname
    // string, which could never match. Now every candidate port-8080 host is
    // verified against /api/status, guaranteeing it is actually our ESP32.
    if (!isReachable) {
      try {
        final activeIps = await SubnetScanner.scanForEsp32(port: targetPort);
        for (final candidateIp in activeIps) {
          final response = await http
              .get(Uri.parse('http://$candidateIp:$targetPort/api/status'))
              .timeout(const Duration(seconds: 2));

          if (response.statusCode == 200) {
            isReachable = true;

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('esp32_ip', candidateIp);
            setState(() {
              deviceIp = candidateIp;
            });
            _addLog("[INFO] Found device via subnet scan at $candidateIp");
            break;
          }
        }
      } catch (_) {
        isReachable = false;
      }
    }

    setState(() {
      _isDeviceConnected = isReachable;
      _isCheckingConnection = false;
    });

    if (isReachable) {
      _addLog("[SUCCESS] Device $deviceIp:$devicePort is ONLINE.");
    } else {
      _addLog("[OFFLINE] No device reachable at $deviceIp:$devicePort.");
    }
  }

  void _addLog(String logText) {
    setState(() {
      cmdLogs.add(logText);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- RELAY TOGGLE ---
  Future<void> _toggleRelay(int relayNumber) async {
    if (_busyRelays.contains(relayNumber)) {
      return;
    }

    String payloadKey;
    String relayLabel;
    bool isTurningOn;

    if (relayNumber == 1) {
      isTurningOn = !relay1State;
      payloadKey = isTurningOn ? 'relay1_on' : 'relay1_off';
      relayLabel = relay1Name;
    } else {
      isTurningOn = !relay2State;
      payloadKey = isTurningOn ? 'relay2_on' : 'relay2_off';
      relayLabel = relay2Name;
    }

    setState(() {
      _busyRelays.add(relayNumber);
      if (relayNumber == 1) relay1State = isTurningOn;
      if (relayNumber == 2) relay2State = isTurningOn;
    });

    _addLog("[$relayLabel] Sending command ($commMode mode)...");

    try {
      final response = await _controlService.sendRelayCommand(
        payloadKey: payloadKey,
      );

      if (response['success'] == true) {
        _addLog("[SUCCESS - ${response['method']}] ${response['message']}");

        if (mounted) {
          setState(() => _isDeviceConnected = true);
        }
      } else {
        _addLog("[ERROR] ${response['message']}");
        if (mounted) {
          setState(() {
            if (relayNumber == 1) relay1State = !isTurningOn;
            if (relayNumber == 2) relay2State = !isTurningOn;
          });
        }
      }
    } catch (e) {
      _addLog("[ERROR] Command failed: $e");
      if (mounted) {
        setState(() {
          if (relayNumber == 1) relay1State = !isTurningOn;
          if (relayNumber == 2) relay2State = !isTurningOn;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyRelays.remove(relayNumber);
        });
      }
    }
  }

  // --- VOICE TOGGLE ---
  Future<void> _handleVoiceToggle(bool newValue) async {
    setState(() => _isVoiceLoading = true);

    _addLog("[VOICE] Setting state to ${newValue ? 'ON' : 'OFF'}...");

    final response = await _controlService.toggleVoiceRecognition(newValue);

    if (response['success'] == true) {
      setState(() {
        _voiceEnabled = newValue;
        _isDeviceConnected = true;
      });
      _addLog("[SUCCESS - ${response['method']}] ${response['message']}");
    } else {
      _addLog("[ERROR] ${response['message']}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update Voice Recognition')),
        );
      }
    }

    setState(() => _isVoiceLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text(
          'Control Dashboard',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            tooltip: 'Device Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddDeviceScreen(),
                ),
              );
              _loadDeviceConfiguration();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _checkDeviceReachability,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isCheckingConnection
                              ? const SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.blueAccent,
                                  ),
                                )
                              : AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isDeviceConnected
                                        ? Colors.green
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      if (_isDeviceConnected)
                                        BoxShadow(
                                          color: Colors.green.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                    ],
                                  ),
                                ),
                          const SizedBox(width: 8),
                          Text(
                            "$deviceIp:$devicePort",
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.refresh_rounded,
                            size: 13,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _cycleCommMode,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _getModeColor(commMode).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getModeColor(commMode).withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getModeIcon(commMode),
                            size: 13,
                            color: _getModeColor(commMode),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            commMode.toUpperCase(),
                            style: TextStyle(
                              color: _getModeColor(commMode),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  title: const Text(
                    'Voice Recognition',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    _voiceEnabled
                        ? 'Microphone is active'
                        : 'Microphone bypassed',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _voiceEnabled
                          ? Colors.blueAccent.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _voiceEnabled ? Icons.mic : Icons.mic_off,
                      color: _voiceEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                  value: _voiceEnabled,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (_isVoiceLoading) ? null : _handleVoiceToggle,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildRelayCard(1, relay1Name, relay1State)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildRelayCard(2, relay2Name, relay2State)),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal, color: Colors.white54, size: 16),
                          SizedBox(width: 8),
                          Text(
                            "SYSTEM LOG",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      Expanded(
                        child: ListView.builder(
                          controller: _terminalScrollController,
                          itemCount: cmdLogs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 3.0,
                              ),
                              child: Text(
                                "> ${cmdLogs[index]}",
                                style: const TextStyle(
                                  color: Color(0xFF4AF626),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelayCard(int relayNum, String name, bool isOn) {
    final bool isBusy = _busyRelays.contains(relayNum);

    return GestureDetector(
      onTap: (isBusy) ? null : () => _toggleRelay(relayNum),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: (isOn ? Colors.black87 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn ? Colors.black87 : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isOn
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            if (isBusy)
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: isOn ? Colors.white : Colors.black87,
                ),
              )
            else
              Icon(
                Icons.power_settings_new_rounded,
                size: 32,
                color: (isOn ? Colors.white : Colors.grey[400]),
              ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: (isOn ? Colors.white : Colors.black87),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (isBusy ? "SENDING..." : (isOn ? "ON" : "OFF")),
              style: TextStyle(
                color: (isBusy
                    ? (isOn ? Colors.white70 : Colors.blueAccent)
                    : (isOn ? Colors.greenAccent : Colors.grey[500])),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
