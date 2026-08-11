import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_device_screen.dart';
import 'relay_control_service.dart';

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

  // Check if IP/mDNS device is reachable via HTTP with graceful fallback handling
  Future<void> _checkDeviceReachability() async {
    if (_isCheckingConnection) return;

    setState(() {
      _isCheckingConnection = true;
    });

    _addLog("[INFO] Checking reachability: $deviceIp:$devicePort...");

    try {
      // Attempt to fetch status to verify local HTTP reachability with a strict timeout wrapper if supported
      bool isReachable = await _controlService.getVoiceStatus(deviceIp, devicePort);
      
      setState(() {
        _isDeviceConnected = isReachable;
      });

      if (isReachable) {
        _addLog("[SUCCESS] Device at $deviceIp:$devicePort is online (HTTP active).");
      } else {
        _addLog("[WARNING] Local HTTP endpoint unresponsive. Hybrid MQTT fallback ready.");
      }
    } catch (e) {
      // Do not falsely crash state; keep last known state or mark hybrid ready
      _addLog("[INFO] HTTP check skipped/failed ($e). MQTT/Hybrid routing active.");
    } finally {
      setState(() {
        _isCheckingConnection = false;
      });
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
              // 1. DYNAMIC TARGET DEVICE PILL (Interactive Ping Indicator)
              Center(
                child: GestureDetector(
                  onTap: _checkDeviceReachability, // Tap to refresh connection state
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
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
                                        color: Colors.green.withOpacity(0.4),
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
              const SizedBox(height: 24),

              // 2. VOICE RECOGNITION CARD
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
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
                      color: _voiceEnabled ? Colors.blueAccent.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _voiceEnabled ? Icons.mic : Icons.mic_off,
                      color: _voiceEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                  value: _voiceEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: _isVoiceLoading ? null : _handleVoiceToggle,
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
              const SizedBox(height: 24),

              // 4. TERMINAL LOG AREA
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
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

  // Minimalist Relay Button Builder
  Widget _buildRelayCard(int relayNum, String name, bool isOn) {
    return GestureDetector(
      onTap: () => _toggleRelay(relayNum),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: isOn ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOn ? Colors.black87 : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isOn ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.02),
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
              color: isOn ? Colors.white : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isOn ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOn ? "ON" : "OFF",
              style: TextStyle(
                color: isOn ? Colors.greenAccent : Colors.grey[500],
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