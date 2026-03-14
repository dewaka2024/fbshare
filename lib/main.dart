import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/theme_provider.dart'; // also exports AppTheme
import 'providers/automation_provider.dart';
import 'providers/template_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AutomationProvider()),

        // TemplateProvider is independent — loads saved templates from prefs.
        ChangeNotifierProvider(create: (_) => TemplateProvider()),

        // ChangeNotifierProxyProvider updates the EXISTING AutomationProvider
        // (created above) whenever TemplateProvider notifies — it does NOT
        // create a second instance. This is the correct way to sync two
        // ChangeNotifiers without the null-bang crash that ProxyProvider causes.
        ChangeNotifierProxyProvider<TemplateProvider, AutomationProvider>(
          // create returns the already-registered instance from the tree.
          create: (ctx) => ctx.read<AutomationProvider>(),
          update: (_, tpl, auto) {
            auto?.setActiveTemplateLabel(tpl.activeLabel);
            return auto!;
          },
        ),
      ],
      child: const FbShareApp(),
    ),
  );
}

class FbShareApp extends StatelessWidget {
  const FbShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'FB Share Automation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const HomeScreen(),
    );
  }
}
