import 'dart:async'; // Required for Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'add_device_screen.dart';
import 'relay_control_service.dart';
import 'subnet_scanner.dart'; // Direct Subnet IP Scanner Integration
import 'demo_service.dart'; // Demo Timer Service

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Service Integration
  final RelayControlService _controlService = RelayControlService();

  // Device Network Target
  String deviceIp = "esp32-s3-inverter.local";
  String devicePort = "8080";

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

  // Terminal Log Output & Controller
  final List<String> cmdLogs = [
    "System Initialized.",
    "Ready for local HTTP or MQTT fallback commands..."
  ];
  final ScrollController _terminalScrollController = ScrollController();

  // Demo Countdown Timer State
  Timer? _demoCountdownTimer;
  int _remainingSeconds = 1200; // 20 minutes default
  bool _isDemoExpired = false;
  bool _isVerifyingTime = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceConfiguration();
    _initializeDemoTimer(); // Initialize Global Demo Countdown
  }

  @override
  void dispose() {
    _demoCountdownTimer?.cancel();
    _terminalScrollController.dispose();
    super.dispose();
  }

  // Load target IP, port, and relay names from SharedPreferences
  Future<void> _loadDeviceConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      deviceIp = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      devicePort = prefs.getString('esp32_port') ?? '8080';

      relay1Name = prefs.getString('relay1_name') ?? 'Relay 1';
      relay2Name = prefs.getString('relay2_name') ?? 'Relay 2';
    });

    await _checkDeviceReachability();
  }

  // Initialize and verify global internet time for trial countdown
  Future<void> _initializeDemoTimer() async {
    _addLog("[DEMO] Verifying trial remaining time...");
    final remaining = await DemoService.getRemainingSeconds();

    if (!mounted) return;

    setState(() {
      _isVerifyingTime = false;
    });

    if (remaining == -1) {
      _addLog("[DEMO ERROR] Internet connection required for time validation.");
      _lockApp("An active internet connection is required to verify the demo trial period.");
    } else if (remaining <= 0) {
      _addLog("[DEMO EXPIRED] Trial period ended.");
      _lockApp("Your 20-minute trial period has ended. All controls are now permanently disabled.");
    } else {
      _addLog("[DEMO] Trial active. $remaining seconds remaining.");
      setState(() {
        _remainingSeconds = remaining;
      });
      _startLiveTimer();
    }
  }

  // Live ticking 1-second countdown loop
  void _startLiveTimer() {
    _demoCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _lockApp("Your 20-minute trial period has ended. All features are now disabled.");
        }
      });
    });
  }

  // Lock application and pop up expired dialog
  void _lockApp(String message) {
    setState(() {
      _isDemoExpired = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDemoExpiredDialog(context, message: message);
    });
  }

  // Format seconds to MM:SS string
  String _formatTimerText(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // Check reachability strictly using direct HTTP probe and SubnetScanner
  Future<void> _checkDeviceReachability() async {
    if (_isCheckingConnection) return;

    setState(() {
      _isCheckingConnection = true;
    });

    _addLog("[INFO] Verifying device at $deviceIp:$devicePort...");

    final targetPort = int.tryParse(devicePort) ?? 8080;
    bool isReachable = false;

    try {
      // Step 1: Direct HTTP ping with strict 2-second timeout
      final pingUri = Uri.parse('http://$deviceIp:$devicePort/api/status');
      final response = await http.get(pingUri).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        isReachable = true;
      }
    } catch (_) {
      isReachable = false;
    }

    // Step 2: Subnet Scanner fallback check if direct HTTP probe failed
    if (!isReachable) {
      try {
        final activeIps = await SubnetScanner.scanForEsp32(port: targetPort);
        // Strictly match target IP address
        if (activeIps.contains(deviceIp)) {
          isReachable = true;
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

  // Add message to terminal screen log and auto-scroll
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

  // Smart Hybrid Toggle: Local HTTP First -> Fallback to MQTT
  Future<void> _toggleRelay(int relayNumber) async {
    // Block action if demo expired
    if (_isDemoExpired) {
      showDemoExpiredDialog(
        context, 
        message: "Demo expired. Please contact the vendor to get the full application.",
      );
      return;
    }

    String payloadKey;
    String relayLabel;
    bool isTurningOn;

    if (relayNumber == 1) {
      isTurningOn = !relay1State;
      payloadKey = isTurningOn ? 'relay1_on' : 'relay1_off';
      relayLabel = relay1Name;
      setState(() => relay1State = isTurningOn); // Optimistic UI update
    } else {
      isTurningOn = !relay2State;
      payloadKey = isTurningOn ? 'relay2_on' : 'relay2_off';
      relayLabel = relay2Name;
      setState(() => relay2State = isTurningOn); // Optimistic UI update
    }

    _addLog("[$relayLabel] Sending command...");
    
    // Delegate entirely to the Service class
    final response = await _controlService.sendRelayCommand(payloadKey: payloadKey);
    
    if (response['success']) {
      _addLog("[SUCCESS - ${response['method']}] ${response['message']}");
      setState(() => _isDeviceConnected = true); // Mark connected on successful command execution
    } else {
      _addLog("[ERROR] ${response['message']}");
      // Revert UI on failure
      setState(() {
        if (relayNumber == 1) relay1State = !isTurningOn;
        if (relayNumber == 2) relay2State = !isTurningOn;
      });
    }
  }

  // Toggle Voice Recognition HTTP/MQTT logic
  Future<void> _handleVoiceToggle(bool newValue) async {
    // Block action if demo expired
    if (_isDemoExpired) {
      showDemoExpiredDialog(
        context, 
        message: "Demo expired. Please contact the vendor to get the full application.",
      );
      return;
    }

    setState(() => _isVoiceLoading = true);
    
    _addLog("[VOICE] Setting state to ${newValue ? 'ON' : 'OFF'}...");
    
    final response = await _controlService.toggleVoiceRecognition(newValue);
    
    if (response['success']) {
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
      backgroundColor: const Color(0xFFF5F7FA), // Minimalist soft background
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
              if (_isDemoExpired) {
                showDemoExpiredDialog(context, message: "Demo time expired.");
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddDeviceScreen()),
              );
              _loadDeviceConfiguration(); 
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 0. DEMO COUNTDOWN TIMER BANNER
              _buildDemoHeaderBanner(),

              // 1. DYNAMIC TARGET DEVICE PILL (Interactive Ping Indicator)
              Center(
                child: GestureDetector(
                  onTap: _checkDeviceReachability, // Tap to re-scan connection state
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dynamic Status Dot or Loading Spinner
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
                                  color: _isDeviceConnected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (_isDeviceConnected)
                                      BoxShadow(
                                        color: Colors.green.withValues(alpha: 0.4),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      )
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
              ),
              const SizedBox(height: 20),

              // 2. VOICE RECOGNITION CARD
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: const Text(
                    'Voice Recognition', 
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87),
                  ),
                  subtitle: Text(
                    _voiceEnabled ? 'Microphone is active' : 'Microphone bypassed',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _voiceEnabled ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _voiceEnabled ? Icons.mic : Icons.mic_off,
                      color: _voiceEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                  value: _voiceEnabled,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (_isVoiceLoading || _isDemoExpired) ? null : _handleVoiceToggle,
                ),
              ),
              const SizedBox(height: 20),

              // 3. RELAY CONTROL CARDS (Grid Layout)
              Row(
                children: [
                  Expanded(child: _buildRelayCard(1, relay1Name, relay1State)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildRelayCard(2, relay2Name, relay2State)),
                ],
              ),
              const SizedBox(height: 20),

              // 4. TERMINAL LOG AREA
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
                      )
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
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
                              padding: const EdgeInsets.symmetric(vertical: 3.0),
                              child: Text(
                                "> ${cmdLogs[index]}",
                                style: const TextStyle(
                                  color: Color(0xFF4AF626), // Classic terminal green
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

  // Demo Countdown Header Banner Widget
  Widget _buildDemoHeaderBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isDemoExpired 
            ? Colors.red.withValues(alpha: 0.1) 
            : Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDemoExpired ? Colors.redAccent : Colors.amber[700]!,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                size: 18,
                color: _isDemoExpired ? Colors.redAccent : Colors.amber[800],
              ),
              const SizedBox(width: 8),
              Text(
                _isVerifyingTime
                    ? "VERIFYING DEMO..."
                    : (_isDemoExpired ? "DEMO EXPIRED" : "DEMO TIME REMAINING"),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _isDemoExpired ? Colors.redAccent : Colors.amber[900],
                ),
              ),
            ],
          ),
          if (!_isVerifyingTime && !_isDemoExpired)
            Text(
              _formatTimerText(_remainingSeconds),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  // Minimalist Relay Button Builder
  Widget _buildRelayCard(int relayNum, String name, bool isOn) {
    return GestureDetector(
      onTap: () => _toggleRelay(relayNum),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: _isDemoExpired 
              ? Colors.grey[200] 
              : (isOn ? Colors.black87 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn ? Colors.black87 : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isOn ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.power_settings_new_rounded,
              size: 32,
              color: _isDemoExpired 
                  ? Colors.grey[400] 
                  : (isOn ? Colors.white : Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isDemoExpired 
                    ? Colors.grey[500] 
                    : (isOn ? Colors.white : Colors.black87),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isDemoExpired ? "LOCKED" : (isOn ? "ON" : "OFF"),
              style: TextStyle(
                color: _isDemoExpired 
                    ? Colors.red[400] 
                    : (isOn ? Colors.greenAccent : Colors.grey[500]),
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Control Dashboard',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50], 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF7C4DFF),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// Expired Demo Dialog Popup
void showDemoExpiredDialog(BuildContext context, {required String message}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text(
                "Demo Time Expired",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                "Contact vendor to obtain the original licensed application.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            )
          ],
        ),
      );
    },
  );
}