import 'package:flutter/material.dart';
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
  String _statusMessage = "";

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

      setState(() {
        _statusMessage = "Configuration saved successfully!";
      });
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
      appBar: AppBar(
        title: const Text('MQTT Command Config'),
        centerTitle: true,
        backgroundColor: const Color(0xFFE91E63),
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
                      const Icon(Icons.tune, size: 60, color: Color(0xFFE91E63)),
                      const SizedBox(height: 16),
                      const Text(
                        'Configure MQTT Topics & Button Commands',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),

                      // MQTT TOPICS
                      const Text(
                        'MQTT Topics',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _cmdTopicController,
                        decoration: const InputDecoration(
                          labelText: 'Command Publish Topic',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.publish),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _statusTopicController,
                        decoration: const InputDecoration(
                          labelText: 'Status Subscribe Topic',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.move_to_inbox),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 12),

                      // RELAY 1 MAPPING
                      const Text(
                        'Relay 1 Button & Payload',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _relay1NameController,
                        decoration: const InputDecoration(
                          labelText: 'Button Label Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _relay1OnCmdController,
                              decoration: const InputDecoration(
                                labelText: 'ON Payload',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _relay1OffCmdController,
                              decoration: const InputDecoration(
                                labelText: 'OFF Payload',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 12),

                      // RELAY 2 MAPPING
                      const Text(
                        'Relay 2 Button & Payload',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _relay2NameController,
                        decoration: const InputDecoration(
                          labelText: 'Button Label Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _relay2OnCmdController,
                              decoration: const InputDecoration(
                                labelText: 'ON Payload',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _relay2OffCmdController,
                              decoration: const InputDecoration(
                                labelText: 'OFF Payload',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // SAVE BUTTON
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE91E63),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _saveCommandConfig,
                        child: const Text('Save Button Settings', style: TextStyle(fontSize: 18)),
                      ),

                      const SizedBox(height: 16),

                      if (_statusMessage.isNotEmpty)
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}