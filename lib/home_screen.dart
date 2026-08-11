import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
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

  // MQTT Credentials & Topics
  String mqttBroker = "";
  String mqttUser = "";
  String mqttPass = "";
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

  // Load target IP/mDNS, port, relay names, MQTT configs, and payloads from SharedPreferences
  Future<void> _loadDeviceConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      deviceIp = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      devicePort = prefs.getString('esp32_port') ?? '8080';

      mqttBroker = prefs.getString('broker_uri') ?? prefs.getString('mqtt_broker') ?? '';
      mqttUser = prefs.getString('broker_user') ?? prefs.getString('mqtt_user') ?? '';
      mqttPass = prefs.getString('broker_pass') ?? prefs.getString('mqtt_pass') ?? '';
      mqttCmdTopic = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';

      relay1Name = prefs.getString('relay1_name') ?? 'Relay 1';
      relay1OnCmd = prefs.getString('relay1_on') ?? '{"relay": 1, "state": 1}';
      relay1OffCmd = prefs.getString('relay1_off') ?? '{"relay": 1, "state": 0}';

      relay2Name = prefs.getString('relay2_name') ?? 'Relay 2';
      relay2OnCmd = prefs.getString('relay2_on') ?? '{"relay": 2, "state": 1}';
      relay2OffCmd = prefs.getString('relay2_off') ?? '{"relay": 2, "state": 0}';
    });
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

    String cleanIp = deviceIp.trim().replaceAll('http://', '').replaceAll('https://', '');
    _addLog("TX -> Attempting LOCAL HTTP to http://$cleanIp:$devicePort/api/relay...");

    // 1. TRY LOCAL HTTP FIRST
    try {
      final localUrl = Uri.parse("http://$cleanIp:$devicePort/api/relay");
      final response = await http
          .post(
            localUrl,
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'close', // Prevents ESP32 socket leak (Error 23)
            },
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
    await _executeMqttFallback(relayLabel, payload);
  }

  // Fallback Command Sender via MQTT Broker
  Future<void> _executeMqttFallback(String relayLabel, String payload) async {
    if (mqttBroker.isEmpty) {
      _addLog("[MQTT ERR] No MQTT Broker configured! Please setup broker details.");
      return;
    }

    try {
      String cleanBroker = mqttBroker
          .replaceAll('mqtts://', '')
          .replaceAll('mqtt://', '')
          .split(':')
          .first;

      final client = MqttServerClient.withPort(
        cleanBroker,
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
        8883,
      );

      client.secure = true;
      client.logging(on: false);
      client.keepAlivePeriod = 20;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_${DateTime.now().millisecondsSinceEpoch}')
          .startClean();
      client.connectionMessage = connMessage;

      _addLog("[MQTT CONNECTING] Connecting to $cleanBroker:8883...");
      await client.connect(mqttUser, mqttPass);

      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(payload);
        client.publishMessage(mqttCmdTopic, MqttQos.atLeastOnce, builder.payload!);

        _addLog("[MQTT SUCCESS] Published to '$mqttCmdTopic' ($relayLabel): $payload");

        await Future.delayed(const Duration(milliseconds: 300));
        client.disconnect();
      } else {
        _addLog("[MQTT ERR] Connection failed: ${client.connectionStatus?.state}");
      }
    } catch (e) {
      _addLog("[MQTT EXCEPTION] $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Control Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Settings',
            onPressed: () {
              _loadDeviceConfiguration();
              _addLog("Device configuration reloaded.");
            },
          )
        ],
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
                    controller: _terminalScrollController,
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