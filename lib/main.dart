// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:path_provider/path_provider.dart';
import 'providers/automation_provider.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize WebView2 environment ONCE before anything else. ────────────
  // webview_windows uses a single WebView2 process per app — calling
  // initializeEnvironment() more than once (or from two concurrent futures)
  // throws PlatformException(unsupported_platform).
  // We init here with a dedicated user-data folder and the mobile UA so
  // Facebook's server always sees a mobile browser.
  try {
    final appSupport = await getApplicationSupportDirectory();
    await WebviewController.initializeEnvironment(
      userDataPath: '${appSupport.path}\\webview2_data',
      additionalArguments:
          '--user-agent="Mozilla/5.0 (Linux; Android 13; SM-S911B) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/116.0.0.0 Mobile Safari/537.36"',
    );
  } catch (e) {
    // Environment may already be initialized on hot-restart — safe to ignore.
    debugPrint('[main] WebView2 init: $e');
  }

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
