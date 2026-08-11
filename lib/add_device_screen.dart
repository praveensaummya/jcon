import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wifi_setup_screen.dart';
import 'mqtt_http_config_screen.dart';
import 'mqtt_cmd_config_screen.dart';

class AddDeviceScreen extends StatelessWidget {
  const AddDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Soft modern background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Device Settings',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon & Text
              const Center(
                child: Icon(Icons.important_devices_rounded, size: 56, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              const Text(
                'Configure Your Hardware',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                'Setup Wi-Fi, assign network targets, and customize your dashboard controls.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),

              // 1. LOCAL CONFIGURATION
              _buildNavigationCard(
                context: context,
                title: 'Wi-Fi Provisioning',
                subtitle: 'Connect ESP32 to your local network via Bluetooth',
                icon: Icons.wifi_rounded,
                iconColor: Colors.purpleAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WifiSetupScreen()),
                  );
                },
              ),

              // 2. MQTT & HTTP CONFIGURATION
              _buildNavigationCard(
                context: context,
                title: 'Network Targets',
                subtitle: 'Set up target IP, ports, and MQTT broker credentials',
                icon: Icons.cloud_sync_rounded,
                iconColor: Colors.blueAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MqttHttpConfigScreen()),
                  );
                },
              ),

              // 3. MQTT CMD CONFIGURATION
              _buildNavigationCard(
                context: context,
                title: 'Button Mapping & Payloads',
                subtitle: 'Customize dashboard buttons, topics, and JSON payloads',
                icon: Icons.tune_rounded,
                iconColor: const Color(0xFFE91E63), // Pink/Magenta
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MqttCmdConfigScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Navigation Card Builder
  Widget _buildNavigationCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Soft tinted circular icon background
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                
                // Text Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Trailing Arrow
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[300], size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}