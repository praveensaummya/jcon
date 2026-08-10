import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart'; // mDNS Discovery Package
import 'dart:convert';

class MqttHttpConfigScreen extends StatefulWidget {
  const MqttHttpConfigScreen({super.key});

  @override
  State<MqttHttpConfigScreen> createState() => _MqttHttpConfigScreenState();
}

class _MqttHttpConfigScreenState extends State<MqttHttpConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Local Device IP / mDNS Host Settings
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8080');

  // MQTT Cloud Broker Settings
  final TextEditingController _brokerController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = true;
  bool _isScanningMdns = false;
  String _statusMessage = "";
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('esp32_ip') ?? 'esp32-s3-inverter.local';
      _portController.text = prefs.getString('esp32_port') ?? '8080';

      _brokerController.text = prefs.getString('mqtt_uri') ?? '';
      _usernameController.text = prefs.getString('mqtt_user') ?? '';
      _passwordController.text = prefs.getString('mqtt_pass') ?? '';

      _isLoading = false;
    });
  }

  // --- mDNS LOCAL NETWORK SCANNER ---
  Future<void> _scanMdnsDevices() async {
    setState(() {
      _isScanningMdns = true;
    });

    List<Service> discoveredServices = [];

    try {
      // Start discovery for HTTP services (_http._tcp)
      final discovery = await startDiscovery('_http._tcp');

      discovery.addListener(() {
        for (var service in discovery.services) {
          if (!discoveredServices.contains(service)) {
            discoveredServices.add(service);
          }
        }
      });

      // Scan for 4 seconds
      await Future.delayed(const Duration(seconds: 4));
      await stopDiscovery(discovery);
    } catch (e) {
      print("mDNS Discovery error: $e");
    }

    setState(() {
      _isScanningMdns = false;
    });

    if (!mounted) return;

    // Display Discovered mDNS Devices in a Bottom Sheet
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Discovered mDNS Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your ESP32-S3 from the list below:',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              discoveredServices.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'No mDNS services found.\nMake sure your ESP32 is powered on and connected to the same Wi-Fi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  : Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: discoveredServices.length,
                        itemBuilder: (context, index) {
                          final service = discoveredServices[index];
                          final hostName = service.host ?? 'esp32-s3-inverter.local';
                          final port = service.port ?? 8080;

                          return ListTile(
                            leading: const Icon(Icons.developer_board, color: Colors.blue),
                            title: Text(service.name ?? hostName),
                            subtitle: Text("Host: $hostName | Port: $port"),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              setState(() {
                                // Auto-populate IP/mDNS host and port
                                _ipController.text = hostName.endsWith('.local')
                                    ? hostName
                                    : '$hostName.local';
                                _portController.text = port.toString();
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAndProvisionDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Saving settings & pushing config to ESP32...";
    });

    final prefs = await SharedPreferences.getInstance();
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final brokerUri = _brokerController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    // Save settings locally
    await prefs.setString('esp32_ip', ip);
    await prefs.setString('esp32_port', port);
    await prefs.setString('mqtt_uri', brokerUri);
    await prefs.setString('mqtt_user', username);
    await prefs.setString('mqtt_pass', password);

    // Push settings to ESP32
    try {
      final url = Uri.parse('http://$ip:$port/api/config/mqtt');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uri': brokerUri,
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        setState(() {
          _isSuccess = true;
          _statusMessage = "Config saved & pushed to ESP32 successfully!";
        });
      } else {
        setState(() {
          _isSuccess = false;
          _statusMessage = "Saved locally! (ESP32 returned status ${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = "Saved locally! Could not reach ESP32 at $ip:$port.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _brokerController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT & HTTP Setup'),
        centerTitle: true,
        backgroundColor: const Color(0xFF42A5F5),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.settings_ethernet, size: 50, color: Color(0xFF42A5F5)),
                      const SizedBox(height: 12),
                      const Text(
                        'Device Network & Broker Settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),

                      // SECTION 1: ESP32 ADDRESS WITH mDNS SEARCH BUTTON
                      const Text(
                        '1. ESP32 Local Address (IP / mDNS)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _ipController,
                              decoration: InputDecoration(
                                labelText: 'IP or Hostname',
                                hintText: 'esp32-s3-inverter.local',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.dns),
                                suffixIcon: _isScanningMdns
                                    ? const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.search, color: Colors.blue),
                                        tooltip: 'Search mDNS Devices',
                                        onPressed: _scanMdnsDevices,
                                      ),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 12),

                      // SECTION 2: MQTT BROKER CREDENTIALS
                      const Text(
                        '2. Cloud MQTT Broker Settings',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _brokerController,
                        decoration: const InputDecoration(
                          labelText: 'MQTT Broker URI',
                          hintText: 'mqtts://broker.hivemq.com:8883',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cloud_queue),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'MQTT Username',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'MQTT Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // SUBMIT BUTTON
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF42A5F5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _saveAndProvisionDevice,
                        icon: const Icon(Icons.save),
                        label: const Text('Save & Sync with Device', style: TextStyle(fontSize: 16)),
                      ),

                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isSuccess ? Colors.green : Colors.orange[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}