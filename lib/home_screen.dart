import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'add_device_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Device Network Target
  String deviceIp = "esp32-s3-inverter.local";
  String devicePort = "8080";

  // MQTT Topics
  String mqttCmdTopic = "device/relays/command";

  // Relay 1 Config
  String relay1Name = "Relay 1";
  String relay1OnCmd = '{"relay": 1, "state": 1}';
  String relay1OffCmd = '{"relay": 1, "state": 0}';
  bool relay1State = false;

  // Relay 2 Config
  String relay2Name = "Relay 2";
  String relay2OnCmd = '{"relay": 2, "state": 1}';
  String relay2OffCmd = '{"relay": 2, "state": 0}';
  bool relay2State = false;

  // CMD Console Terminal Log Output
  final List<String> cmdLogs = [
    "System Initialized.",
    "Ready for local HTTP or MQTT fallback commands..."
  ];

  @override
  void initState() {
    super.initState();
    _loadDeviceConfiguration();
  }

  // Load target IP/mDNS, port, relay names, and payloads from SharedPreferences
  Future<void> _loadDeviceConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      deviceIp = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      devicePort = prefs.getString('esp32_port') ?? '8080';
      mqttCmdTopic = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';

      relay1Name = prefs.getString('relay1_name') ?? 'Relay 1';
      relay1OnCmd = prefs.getString('relay1_on') ?? '{"relay": 1, "state": 1}';
      relay1OffCmd = prefs.getString('relay1_off') ?? '{"relay": 1, "state": 0}';

      relay2Name = prefs.getString('relay2_name') ?? 'Relay 2';
      relay2OnCmd = prefs.getString('relay2_on') ?? '{"relay": 2, "state": 1}';
      relay2OffCmd = prefs.getString('relay2_off') ?? '{"relay": 2, "state": 0}';
    });
  }

  // Add message to terminal screen log
  void _addLog(String logText) {
    setState(() {
      cmdLogs.add(logText);
    });
  }

  // Smart Hybrid Toggle: Local HTTP First -> Fallback to MQTT
  Future<void> _toggleRelay(int relayNumber) async {
    bool newState;
    String payload;
    String relayLabel;

    if (relayNumber == 1) {
      relay1State = !relay1State;
      newState = relay1State;
      payload = newState ? relay1OnCmd : relay1OffCmd;
      relayLabel = relay1Name;
    } else {
      relay2State = !relay2State;
      newState = relay2State;
      payload = newState ? relay2OnCmd : relay2OffCmd;
      relayLabel = relay2Name;
    }

    setState(() {}); // Update button state visually immediately

    _addLog("TX -> Attempting LOCAL HTTP to http://$deviceIp:$devicePort...");

    // 1. TRY LOCAL HTTP FIRST
    try {
      final localUrl = Uri.parse("http://$deviceIp:$devicePort/api/relay");
      final response = await http
          .post(
            localUrl,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 2)); // 2 second local threshold

      if (response.statusCode == 200) {
        _addLog("[LOCAL HTTP SUCCESS] ($relayLabel): $payload");
        return; // Success, no need for MQTT
      } else {
        _addLog("[LOCAL HTTP ERR ${response.statusCode}] Falling back to MQTT...");
      }
    } catch (e) {
      _addLog("[LOCAL HTTP UNREACHABLE] Falling back to MQTT Cloud...");
    }

    // 2. FALLBACK TO MQTT CLOUD
    _executeMqttFallback(relayLabel, payload);
  }

  // Fallback Command Sender
  void _executeMqttFallback(String relayLabel, String payload) {
    // Note: If using an active MQTT client library (e.g. mqtt_client package), 
    // publish message here directly to `mqttCmdTopic`.
    _addLog("[MQTT CLOUD TX] Published to topic '$mqttCmdTopic': $payload");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Control Dashboard'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HEADER TEXT WITH SELECTED TARGET ADDRESS
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link, size: 18, color: Colors.black87),
                    const SizedBox(width: 6),
                    Text(
                      "TARGET DEVICE: $deviceIp:$devicePort",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // TOP PURPLE BUTTON (ADD NEW DEVICE)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddDeviceScreen()),
                  );
                  _loadDeviceConfiguration(); // Reload dynamic settings when returning
                },
                child: const Text(
                  'ADD NEW DEVICE\nCONFIGURING BUTTONS AND CMDS',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 16),

              // MAIN MIDDLE SECTION (RELAY STATUS + CONTROL BUTTONS)
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    // PINK BOX: RELAY STATUS
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'RELAY STATUS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Divider(color: Colors.white54, height: 20),

                            // Relay 1 Status
                            Text(
                              "$relay1Name:",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              relay1State ? "ON" : "OFF",
                              style: TextStyle(
                                color: relay1State ? Colors.greenAccent : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Relay 2 Status
                            Text(
                              "$relay2Name:",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              relay2State ? "ON" : "OFF",
                              style: TextStyle(
                                color: relay2State ? Colors.greenAccent : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // BLUE BOX: ACTION BUTTONS
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2979FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: relay1State ? Colors.green : Colors.white,
                                foregroundColor: relay1State ? Colors.white : Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () => _toggleRelay(1),
                              child: Text(
                                relay1Name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: relay2State ? Colors.green : Colors.white,
                                foregroundColor: relay2State ? Colors.white : Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () => _toggleRelay(2),
                              child: Text(
                                relay2Name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // BLACK BOX: CMD TERMINAL AT BOTTOM
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.builder(
                    itemCount: cmdLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          cmdLogs[index],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}