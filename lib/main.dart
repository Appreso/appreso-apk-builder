import 'package:flutter/material.dart';
import 'dart:async';
import 'config/app_config.dart';
import 'screens/splash_screen.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = await AppConfig.load();
    runApp(AppResoApp(config: config));
  }, (error, stack) {
    debugPrint('App Error: $error\n$stack');
  });
}

class AppResoApp extends StatelessWidget {
  final AppConfig config;
  
  const AppResoApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366f1)),
        useMaterial3: true,
      ),
      home: SplashScreen(config: config),
    );
  }
}
