// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/automation_provider.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AutomationProvider(),
      child: const FbShareApp(),
    ),
  );
}

class FbShareApp extends StatelessWidget {
  const FbShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FB Share Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        colorScheme: const ColorScheme.dark(
          surface:   Color(0xFF141720),
          primary:   Color(0xFF1877F2),
          secondary: Color(0xFF448AFF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
