import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'subnet_scanner.dart'; // Direct Subnet IP Scanner

/// Network + broker configuration screen.
///
/// Saves to SharedPreferences: `esp32_ip` / `esp32_port` (device target),
/// `mqtt_uri` / `mqtt_user` / `mqtt_pass` (cloud broker, TLS, used as the
/// fallback/push path) and `comm_mode` (`auto` | `http` | `mqtt`).
/// Also hosts the one-tap subnet scan that fills the IP field, and the
/// "test" button that verifies the device with `GET /api/status`.
class MqttHttpConfigScreen extends StatefulWidget {
  const MqttHttpConfigScreen({super.key});

  @override
  State<MqttHttpConfigScreen> createState() => _MqttHttpConfigScreenState();
}

class _MqttHttpConfigScreenState extends State<MqttHttpConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Local Device IP / Host Settings
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8080');

  // MQTT Cloud Broker Settings
  final TextEditingController _brokerController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Communication Preference Mode ('auto', 'http', 'mqtt')
  String _commMode = 'auto';

  bool _isLoading = true;
  bool _isScanningSubnet = false;
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
      _ipController.text = prefs.getString('esp32_ip') ?? 'esp32-inverter.local';
      _portController.text = prefs.getString('esp32_port') ?? '8080';

      _brokerController.text = prefs.getString('mqtt_uri') ?? '';
      _usernameController.text = prefs.getString('mqtt_user') ?? '';
      _passwordController.text = prefs.getString('mqtt_pass') ?? '';

      // Load saved communication mode (defaults to 'auto')
      _commMode = prefs.getString('comm_mode') ?? 'auto';

      _isLoading = false;
    });
  }

  // --- FAST PARALLEL SUBNET SCANNER ---
  Future<void> _scanSubnetDevices() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isScanningSubnet = true;
      _statusMessage = "";
    });

    final targetPort = int.tryParse(_portController.text.trim()) ?? 8080;
    final discoveredIps = await SubnetScanner.scanForEsp32(port: targetPort);

    setState(() {
      _isScanningSubnet = false;
    });

    if (!mounted) return;

    // Display Discovered IP Addresses in a Bottom Sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'Discovered Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                'Active devices responding on port $targetPort:',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              discoveredIps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'No devices found on port $targetPort.\nEnsure your ESP32 is powered on and connected to the same Wi-Fi network.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red[400], height: 1.5),
                      ),
                    )
                  : Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: discoveredIps.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey[200]),
                        itemBuilder: (context, index) {
                          final ip = discoveredIps[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.developer_board, color: Colors.blueAccent),
                              ),
                              title: const Text('ESP32-S3 Node', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(ip, style: const TextStyle(color: Colors.black54)),
                              trailing: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _ipController.text = ip;
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Selected IP: $ip'),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: const Text('SELECT'),
                              ),
                            ),
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

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _statusMessage = "Saving settings & verifying connection...";
    });

    final prefs = await SharedPreferences.getInstance();
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    final brokerUri = _brokerController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    // Save all configuration parameters including communication mode
    await prefs.setString('esp32_ip', ip);
    await prefs.setString('esp32_port', port);
    await prefs.setString('mqtt_uri', brokerUri);
    await prefs.setString('mqtt_user', username);
    await prefs.setString('mqtt_pass', password);
    await prefs.setString('comm_mode', _commMode);

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
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        setState(() {
          _isSuccess = true;
          _statusMessage = "Network config saved & verified with ESP32!";
        });
      } else {
        setState(() {
          _isSuccess = false;
          _statusMessage = "Saved locally! (Device returned status ${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = "Settings saved locally for Home Screen connection.";
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Device Setup',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading && _statusMessage.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.router_rounded, size: 48, color: Colors.blueAccent),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Network & Broker Sync',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 32),

                      // SECTION 1: DEVICE NETWORK SETTINGS
                      const Text(
                        '1. Target Device IP Address',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _ipController,
                              decoration: InputDecoration(
                                labelText: 'IP or mDNS (esp32.local)',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: const Icon(Icons.dns_outlined, color: Colors.black54),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Port',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blueAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isScanningSubnet ? null : _scanSubnetDevices,
                          icon: _isScanningSubnet
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.radar),
                          label: Text(_isScanningSubnet ? 'Scanning Network...' : 'Scan Local Subnet for Device'),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // SECTION 2: COMMUNICATION PREFERENCE MODE
                      const Text(
                        '2. Communication Preference Mode',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select direct route to avoid fallback timeouts when away from home Wi-Fi:',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 12),

                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'auto',
                            label: Text('Auto'),
                            icon: Icon(Icons.sync_alt_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'http',
                            label: Text('HTTP Only'),
                            icon: Icon(Icons.wifi_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'mqtt',
                            label: Text('MQTT Only'),
                            icon: Icon(Icons.cloud_rounded, size: 16),
                          ),
                        ],
                        selected: {_commMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _commMode = newSelection.first;
                          });
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),
                      const Divider(height: 1),
                      const SizedBox(height: 28),

                      // SECTION 3: CLOUD MQTT FALLBACK
                      const Text(
                        '3. Cloud MQTT Fallback',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _brokerController,
                        decoration: InputDecoration(
                          labelText: 'MQTT Broker URI',
                          hintText: 'mqtts://dddfssfsfsfse.s1.eu.hivemq.cloud',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.cloud_queue, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'MQTT Username (Optional)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.person_outline, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'MQTT Password (Optional)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
                        ),
                      ),

                      const SizedBox(height: 40),

                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _isLoading ? null : _saveAndProvisionDevice,
                          icon: _isLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                          label: const Text('Save & Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: _isSuccess ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _isSuccess ? Colors.green : Colors.orange)),
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isSuccess ? Colors.green[800] : Colors.orange[900],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}