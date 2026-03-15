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
      title: 'FB Share Automation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          surface:   Color(0xFF1E1E1E),
          primary:   Color(0xFF2979FF),
          secondary: Color(0xFF448AFF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
