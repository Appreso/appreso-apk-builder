import 'dart:async';
import 'package:flutter/material.dart';
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
    
    // Ensure splash is visible for at least 2 seconds
    final results = await Future.wait([
      verificationService.verify(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    final bool isVerified = results[0] as bool;

    if (!mounted) return;

    if (isVerified) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WebViewScreen(config: widget.config)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ErrorScreen(
            config: widget.config,
            errorMessage: 'The plugin is not active on this website. Please contact the site administrator to re-activate the AppReso plugin.',
          ),
        ),
      );
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                widget.config.appName,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            const AppResoLoader(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
