import 'package:flutter/material.dart';
import 'telemetry_ban_service.dart';

/// Alias function to preserve compatibility with home_screen.dart calls
Future<void> showContactRegistrationDialog(BuildContext context) async {
  return showContactInfoDialog(context);
}

/// Displays the mandatory Contact Registration dialog popup
Future<void> showContactInfoDialog(BuildContext context) async {
  await showDialog(
    context: context,
    barrierDismissible: false, // User must complete dialog before proceeding
    builder: (context) => const _ContactRegistrationDialogWidget(),
  );
}

class _ContactRegistrationDialogWidget extends StatefulWidget {
  const _ContactRegistrationDialogWidget();

  @override
  State<_ContactRegistrationDialogWidget> createState() =>
      __ContactRegistrationDialogWidgetState();
}

class __ContactRegistrationDialogWidgetState
    extends State<_ContactRegistrationDialogWidget> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    // Safely dispose controllers ONLY when the dialog widget is fully unmounted
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Save contact details and set registration flag in TelemetryBanService
      await TelemetryBanService.saveContactInfo(
        _nameController.text.trim(),
        _phoneController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog safely
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: SingleChildScrollView(
        // Prevents RenderFlex overflow when screen keyboard pops up
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_pin_rounded, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text(
                "User Registration",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Please enter your contact details to register this application instance.",
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: "Your Name",
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty)
                          ? "Name is required"
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone / WhatsApp",
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty)
                          ? "Phone is required"
                          : null,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isLoading ? null : _handleSubmit,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("Submit & Continue"),
            ),
          ],
        ),
      ),
    );
  }
}