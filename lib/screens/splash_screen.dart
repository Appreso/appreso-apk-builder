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

    // Always navigate after max 6 seconds, no matter what
    VerificationResult? verification;
    PackageInfo? packageInfo;
    
    try {
      // Run verification and package info in parallel
      final verifyFuture = verificationService.verify().timeout(const Duration(seconds: 4));
      final packageFuture = PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
      
      // Minimum splash display time
      await Future.delayed(const Duration(seconds: 2));
      
      try {
        verification = await verifyFuture;
      } catch (e) {
        debugPrint('Verification failed: $e');
        verification = VerificationResult(isActive: true, latestVersion: '1.0.0', minVersion: '1.0.0', forceUpdate: false, updateTitle: '', updateMessage: '', apkUrl: '');
      }
      
      try {
        packageInfo = await packageFuture;
      } catch (e) {
        debugPrint('PackageInfo failed: $e');
      }
    } catch (e) {
      debugPrint('Splash check exception: $e');
    }

    if (!mounted) return;

    // Check verification result
    if (verification != null && !verification.isActive) {
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

    // In-App Version & Force Update Check
    if (verification != null && packageInfo != null) {
      final currentVer = packageInfo.version;
      final latestVer = verification.latestVersion;
      final minVer = verification.minVersion;

      if (_isOlderVersion(currentVer, latestVer)) {
        final bool isForce = verification.forceUpdate || _isOlderVersion(currentVer, minVer);
        _showUpdateDialog(
          currentVersion: currentVer,
          latestVersion: latestVer,
          title: verification.updateTitle,
          message: verification.updateMessage,
          apkUrl: verification.apkUrl.isNotEmpty ? verification.apkUrl : widget.config.siteUrl,
          isForce: isForce,
        );
        return;
      }
    }

    // Navigate to WebView - THIS ALWAYS RUNS
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WebViewScreen(config: widget.config)),
    );
  }

  bool _isOlderVersion(String current, String target) {
    try {
      final cleanCurrent = current.split('+')[0].trim();
      final cleanTarget = target.split('+')[0].trim();
      
      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final targetParts = cleanTarget.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      for (var i = 0; i < targetParts.length; i++) {
        final curr = i < currentParts.length ? currentParts[i] : 0;
        final targ = targetParts[i];
        if (curr < targ) return true;
        if (curr > targ) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _showUpdateDialog({
    required String currentVersion,
    required String latestVersion,
    required String title,
    required String message,
    required String apkUrl,
    required bool isForce,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (dialogContext) => PopScope(
        canPop: !isForce,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Icon / Header Badge
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.rocket_launch_rounded,
                      size: 38,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Text(
                  title.isNotEmpty ? title : 'New Version Available!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),

                // Version Badge (v1.0.0 -> v1.2.0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'v$currentVersion',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF6366F1)),
                      ),
                      Text(
                        'v$latestVersion',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Changelog / Message Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      message.isNotEmpty ? message : 'A new version with improvements and bug fixes is ready for you.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Primary Action Button (Download & Update Now)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(apkUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'Download & Update Now',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

                // Optional "Later" button for non-force updates
                if (!isForce) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => WebViewScreen(config: widget.config)),
                      );
                    },
                    child: Text(
                      'Remind Me Later',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
