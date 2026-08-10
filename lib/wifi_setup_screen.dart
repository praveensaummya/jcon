import 'package:flutter/material.dart';
import 'wifi_provisioning_service.dart';

class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  final TextEditingController _ipController = TextEditingController(text: '10.10.0.1');
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final WifiProvisioningService _provisioningService = WifiProvisioningService();

  bool _isLoading = false;
  String _statusMessage = "";
  
  // NEW: State variables for IP checking
  bool _isCheckingIp = false;
  bool? _isIpConnected; // null = untested, true = connected, false = failed

  // NEW: Method to verify the IP connection
  Future<void> _verifyIpConnection() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _isCheckingIp = true;
      _isIpConnected = null;
      _statusMessage = "Verifying connection to ESP32...";
    });

    bool isConnected = await _provisioningService.checkConnection(ip);

    setState(() {
      _isCheckingIp = false;
      _isIpConnected = isConnected;
      if (isConnected) {
        _statusMessage = "Connected to ESP32 successfully!";
      } else {
        _statusMessage = "Could not reach ESP32. Are you connected to its hotspot?";
      }
    });
  }

  Future<void> _scanForNetworks() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _statusMessage = "Please enter a valid IP address.");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List<dynamic> networks = await _provisioningService.getAvailableNetworks(ip);
    
    if (mounted) Navigator.pop(context);

    if (networks.isEmpty) {
      setState(() {
        _statusMessage = "No networks found. Check your VS Code Debug Console for errors.";
      });
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Select a WI-FI Network",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final net = networks[index];
                    bool requiresPassword = net['auth'] != 0;

                    return ListTile(
                      leading: Icon(
                        Icons.wifi,
                        color: net['rssi'] > -70 ? Colors.green : Colors.orange,
                      ),
                      title: Text(net['ssid']),
                      subtitle: Text('Signal: ${net['rssi']} dBm'),
                      trailing: requiresPassword ? const Icon(Icons.lock, size: 16) : null,
                      onTap: () {
                        setState(() {
                          _ssidController.text = net['ssid'];
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              )
            ],
          );
        },
      );
    }
  }

  Future<void> _submitCredentials() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _statusMessage = "Please enter a valid IP address.");
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Sending credentials to ESP32 at $ip...";
    });

    bool success = await _provisioningService.sendWifiCredentials(
      ip,
      _ssidController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() {
      _isLoading = false;
      if (success) {
        _statusMessage = "Success! ESP32 is now rebooting to connect.";
      } else {
        _statusMessage = "Failed. Make sure you are connected to ESP32's WI-FI hotspot.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 WI-FI Setup'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // const Icon(Icons.wifi, size: 80, color: Colors.blue),
                // const SizedBox(height: 24),
                
                // UPDATED IP Field with Status Indicator
                TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'ESP32 IP Address',
                    hintText: '10.10.0.1 or 192.168.1.27',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.dns),
                    suffixIcon: _isCheckingIp 
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(
                              _isIpConnected == null ? Icons.help_outline :
                              _isIpConnected! ? Icons.check_circle : Icons.error,
                              color: _isIpConnected == null ? Colors.grey :
                                     _isIpConnected! ? Colors.green : Colors.red,
                            ),
                            tooltip: 'Verify Connection',
                            onPressed: _verifyIpConnection,
                          ),
                  ),
                ),
                
                const SizedBox(height: 16),
                const Text(
                  "Connect your phone to the ESP32 hotspot, then enter your home WI-FI details below",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                
                TextField(
                  controller: _ssidController,
                  decoration: InputDecoration(
                    labelText: 'WI-FI Name (SSID)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.router),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.blue),
                      tooltip: 'Scan for networks',
                      onPressed: _scanForNetworks,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitCredentials,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send to ESP32', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 24),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage.toLowerCase().contains("success")
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}