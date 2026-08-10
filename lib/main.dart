import 'package:flutter/material.dart';
import 'home_screen.dart'; 

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