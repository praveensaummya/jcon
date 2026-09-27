/// JCON — Flutter companion app for the ESP32-S3 voice-controlled inverter.
///
/// Entry point: boots [HomeScreen], the dashboard that talks to the ESP32-S3
/// firmware (https://github.com/praveensaummya/en_speech_commands_custom)
/// over local HTTP (`http://esp32-inverter.local:8080`) with cloud MQTT as
/// a fallback. All device communication lives in the `*_service.dart`
/// files; screens only orchestrate them.
library;

import 'package:flutter/material.dart';
import 'home_screen.dart';

/// JCON app entry point.
///
/// Builds the Material 3 shell (purple/blue/pink palette) and mounts
/// [HomeScreen], the single-page dashboard that hosts relay control,
/// voice toggle, device discovery and configuration flows.
void main() {
  // Ensure Flutter bindings are initialized before using SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Control Dashboard',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        // Setting a global theme based on your Purple/Blue/Pink palette
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50], 
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF7C4DFF),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      // Set the newly created HomeScreen as the initial page
      home: const HomeScreen(),
    );
  }
}

