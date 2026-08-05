import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config/app_config.dart';
import '../services/verification_service.dart';
import '../widgets/loading_indicator.dart';
import 'error_screen.dart';
import 'webview_screen.dart';

class SplashScreen extends StatefulWidget {
  final AppConfig config;

  const SplashScreen({super.key, required this.config});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _checkVerification();
  }

  Future<void> _checkVerification() async {
    final verificationService = VerificationService(widget.config);
    
    // Fire analytics in background without blocking splash screen!
    _trackAnalyticsOpen();

    try {
      final results = await Future.wait([
        verificationService.verify().timeout(const Duration(seconds: 5)),
        PackageInfo.fromPlatform().timeout(const Duration(seconds: 3)),
        Future.delayed(const Duration(seconds: 2)),
      ]);

      final VerificationResult verification = results[0] as VerificationResult;
      final PackageInfo packageInfo = results[1] as PackageInfo;

      if (!mounted) return;

      if (!verification.isActive) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ErrorScreen(
              config: widget.config,
              errorMessage: 'The plugin is not active on this website. Please contact the site administrator to re-activate the AppReso plugin.',
            ),
          ),
        );
        return;
      }

      // Force Update Check
      if (_isUpdateRequired(packageInfo.version, verification.requiredVersion)) {
        _showUpdateDialog(verification.updateMessage);
        return;
      }
    } catch (e) {
      debugPrint('Splash check exception: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WebViewScreen(config: widget.config)),
      );
    }
  }

  bool _isUpdateRequired(String current, String required) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final requiredParts = required.split('.').map(int.parse).toList();
      for (var i = 0; i < requiredParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (requiredParts[i] > currentParts[i]) return true;
        if (requiredParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _showUpdateDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse(widget.config.siteUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('UPDATE NOW'),
          ),
        ],
      ),
    );
  }

  Future<void> _trackAnalyticsOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('appreso_device_id');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
        await prefs.setString('appreso_device_id', deviceId);
      }

      await http.post(
        Uri.parse(widget.config.analyticsUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'event': 'app_open',
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      // Silently fail if analytics can't be sent
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.config.splashType == 'color' 
              ? AppConfig.hexToColor(widget.config.splashBgColor) 
              : null,
          image: widget.config.splashType == 'image'
              ? const DecorationImage(
                  image: AssetImage('assets/splash.png'),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.config.splashShowName == 'yes')
              FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  widget.config.splashCustomText.isNotEmpty ? widget.config.splashCustomText : widget.config.appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.hexToColor(widget.config.splashTextColor),
                  ),
                ),
              ),
            if (widget.config.splashShowName == 'yes')
              const SizedBox(height: 40),
            AppResoLoader(color: AppConfig.hexToColor(widget.config.splashTextColor)),
          ],
        ),
      ),
    );
  }
}
