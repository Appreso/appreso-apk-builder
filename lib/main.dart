import 'package:flutter/material.dart';
import 'dart:async';
import 'config/app_config.dart';
import 'screens/splash_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'services/push_service.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = await AppConfig.load();
    
    // Initialize OneSignal Push Notifications if App ID is provided
    if (config.onesignalAppId.isNotEmpty) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(config.onesignalAppId);
      OneSignal.Notifications.requestPermission(true);

      OneSignal.Notifications.addClickListener((event) {
        final additionalData = event.notification.additionalData;
        if (additionalData != null && additionalData.containsKey('launchURL')) {
          final url = additionalData['launchURL'] as String?;
          pushService.handleNotificationClick(url);
        }
      });
    }
    
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
