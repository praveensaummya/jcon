import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  bool _isCheckingIp = false;
  bool? _isIpConnected; // null = untested, true = connected, false = failed

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
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      ),
    );

    List<dynamic> networks = await _provisioningService.getAvailableNetworks(ip);
    
    if (mounted) Navigator.pop(context);

    if (networks.isEmpty) {
      setState(() {
        _statusMessage = "No networks found. Check your debug console.";
      });
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFFF5F7FA),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Select Wi-Fi Network",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: networks.length,
                    itemBuilder: (context, index) {
                      final net = networks[index];
                      bool requiresPassword = net['auth'] != 0;
                      int rssi = net['rssi'] ?? -100;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (rssi > -70 ? Colors.green : Colors.orange).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.wifi_rounded,
                              color: rssi > -70 ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            net['ssid'] ?? 'Unknown Network',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Signal: $rssi dBm',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: requiresPassword 
                              ? Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey[500]) 
                              : null,
                          onTap: () {
                            setState(() {
                              _ssidController.text = net['ssid'] ?? '';
                            });
                            Navigator.pop(context);
                          },
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
        _statusMessage = "Failed. Make sure you are connected to ESP32's hotspot.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Matches modern app background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // CRITICAL: Forces dark system status bar icons (time, battery, signal) so they remain visible on light backgrounds
        systemOverlayStyle: SystemUiOverlayStyle.dark, 
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Wi-Fi Provisioning',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon
              const Center(
                child: Icon(Icons.wifi_tethering_rounded, size: 48, color: Colors.purpleAccent),
              ),
              const SizedBox(height: 12),
              const Text(
                'Connect to ESP32 Hotspot',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                'Connect your phone to the ESP32 network first, then specify your target home Wi-Fi details below.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),

              // CARD 1: ESP32 Target IP
              Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns_rounded, color: Colors.purpleAccent, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          "Access Point Target",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'ESP32 IP Address',
                        hintText: '10.10.0.1 or 192.168.4.1',
                        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                        prefixIcon: Icon(Icons.link_rounded, size: 18, color: Colors.grey[500]),
                        suffixIcon: _isCheckingIp 
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent),
                              )
                            : IconButton(
                                icon: Icon(
                                  _isIpConnected == null ? Icons.help_outline_rounded :
                                  _isIpConnected! ? Icons.check_circle_rounded : Icons.error_rounded,
                                  color: _isIpConnected == null ? Colors.grey :
                                         _isIpConnected! ? Colors.green : Colors.red,
                                ),
                                tooltip: 'Verify Connection',
                                onPressed: _verifyIpConnection,
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // CARD 2: Wi-Fi Credentials
              Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.router_rounded, color: Colors.purpleAccent, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          "Home Network Details",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ssidController,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Wi-Fi Name (SSID)',
                        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                        prefixIcon: Icon(Icons.wifi_rounded, size: 18, color: Colors.grey[500]),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded, color: Colors.purpleAccent),
                          tooltip: 'Scan for networks',
                          onPressed: _scanForNetworks,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey[500]),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // SUBMIT BUTTON
              ElevatedButton(
                onPressed: _isLoading ? null : _submitCredentials,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Send to ESP32',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),

              const SizedBox(height: 16),

              // STATUS MESSAGE
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusMessage.toLowerCase().contains("success")
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.toLowerCase().contains("success")
                          ? Colors.green[800]
                          : Colors.red[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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