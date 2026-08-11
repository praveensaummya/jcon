import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttCmdConfigScreen extends StatefulWidget {
  const MqttCmdConfigScreen({super.key});

  @override
  State<MqttCmdConfigScreen> createState() => _MqttCmdConfigScreenState();
}

class _MqttCmdConfigScreenState extends State<MqttCmdConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _cmdTopicController = TextEditingController();
  final TextEditingController _statusTopicController = TextEditingController();

  final TextEditingController _relay1NameController = TextEditingController();
  final TextEditingController _relay1OnCmdController = TextEditingController();
  final TextEditingController _relay1OffCmdController = TextEditingController();

  final TextEditingController _relay2NameController = TextEditingController();
  final TextEditingController _relay2OnCmdController = TextEditingController();
  final TextEditingController _relay2OffCmdController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  // Load saved preferences on startup
  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cmdTopicController.text = prefs.getString('mqtt_cmd_topic') ?? 'device/relays/command';
      _statusTopicController.text = prefs.getString('mqtt_status_topic') ?? 'device/relays/status';

      _relay1NameController.text = prefs.getString('relay1_name') ?? 'Relay 1';
      _relay1OnCmdController.text = prefs.getString('relay1_on') ?? '{"relay": 1, "state": 1}';
      _relay1OffCmdController.text = prefs.getString('relay1_off') ?? '{"relay": 1, "state": 0}';

      _relay2NameController.text = prefs.getString('relay2_name') ?? 'Relay 2';
      _relay2OnCmdController.text = prefs.getString('relay2_on') ?? '{"relay": 2, "state": 1}';
      _relay2OffCmdController.text = prefs.getString('relay2_off') ?? '{"relay": 2, "state": 0}';

      _isLoading = false;
    });
  }

  // Save settings to persistent storage
  Future<void> _saveCommandConfig() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('mqtt_cmd_topic', _cmdTopicController.text.trim());
      await prefs.setString('mqtt_status_topic', _statusTopicController.text.trim());

      await prefs.setString('relay1_name', _relay1NameController.text.trim());
      await prefs.setString('relay1_on', _relay1OnCmdController.text.trim());
      await prefs.setString('relay1_off', _relay1OffCmdController.text.trim());

      await prefs.setString('relay2_name', _relay2NameController.text.trim());
      await prefs.setString('relay2_on', _relay2OnCmdController.text.trim());
      await prefs.setString('relay2_off', _relay2OffCmdController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Configuration saved successfully!'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cmdTopicController.dispose();
    _statusTopicController.dispose();
    _relay1NameController.dispose();
    _relay1OnCmdController.dispose();
    _relay1OffCmdController.dispose();
    _relay2NameController.dispose();
    _relay2OnCmdController.dispose();
    _relay2OffCmdController.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Match home_screen soft background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Command Config',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      const Center(
                        child: Icon(Icons.tune_rounded, size: 48, color: Colors.blueAccent),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Customize Buttons & Topics',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Define MQTT topics and the exact JSON payloads sent when buttons are pressed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),

                      // Section 1: Topics
                      _buildSectionCard(
                        title: 'MQTT Network Topics',
                        icon: Icons.cell_tower_rounded,
                        children: [
                          _buildTextField(
                            controller: _cmdTopicController,
                            label: 'Command Publish Topic',
                            icon: Icons.publish_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _statusTopicController,
                            label: 'Status Subscribe Topic',
                            icon: Icons.move_to_inbox_rounded,
                          ),
                        ],
                      ),

                      // Section 2: Relay 1
                      _buildSectionCard(
                        title: 'Relay 1 Configuration',
                        icon: Icons.power_settings_new_rounded,
                        children: [
                          _buildTextField(
                            controller: _relay1NameController,
                            label: 'Button Label Name',
                            icon: Icons.label_outline_rounded,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _relay1OnCmdController,
                                  label: 'ON Payload',
                                  icon: Icons.code_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _relay1OffCmdController,
                                  label: 'OFF Payload',
                                  icon: Icons.code_off_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Section 3: Relay 2
                      _buildSectionCard(
                        title: 'Relay 2 Configuration',
                        icon: Icons.power_settings_new_rounded,
                        children: [
                          _buildTextField(
                            controller: _relay2NameController,
                            label: 'Button Label Name',
                            icon: Icons.label_outline_rounded,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _relay2OnCmdController,
                                  label: 'ON Payload',
                                  icon: Icons.code_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _relay2OffCmdController,
                                  label: 'OFF Payload',
                                  icon: Icons.code_off_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Save Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87, // Sleek modern dark button
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _saveCommandConfig,
                        child: const Text('Save Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // Helper function to build modern cards
  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  // Helper function to build modern borderless text fields
  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFFF8F9FA), // Very subtle grey/blue tint inside input
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
    );
  }
}