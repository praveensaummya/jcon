import 'package:flutter/material.dart';
import 'wifi_setup_screen.dart';

void main() {
  runApp(const SmartRelayApp());
}

class SmartRelayApp extends StatelessWidget {
  const SmartRelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Relay Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WifiSetupScreen(),
    );
  }
}