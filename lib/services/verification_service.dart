import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class VerificationResult {
  final bool isActive;
  final String latestVersion;
  final String minVersion;
  final bool forceUpdate;
  final String updateTitle;
  final String updateMessage;
  final String apkUrl;

  VerificationResult({
    required this.isActive,
    required this.latestVersion,
    required this.minVersion,
    required this.forceUpdate,
    required this.updateTitle,
    required this.updateMessage,
    required this.apkUrl,
  });
}

class VerificationService {
  final AppConfig config;

  const VerificationService(this.config);

  Future<VerificationResult> verify() async {
    try {
      var response = await http.get(
        Uri.parse(config.verifyUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AppReso-Android/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        final cleanUrl = config.siteUrl.endsWith('/') ? config.siteUrl.substring(0, config.siteUrl.length - 1) : config.siteUrl;
        response = await http.get(
          Uri.parse('$cleanUrl/wp-json/${config.apiNamespace}/verify'),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'AppReso-Android/1.0',
          },
        ).timeout(const Duration(seconds: 4));
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          final isForce = data['force_update'] == true || data['force_update']?.toString() == 'yes';
          return VerificationResult(
            isActive: data['active'] == true,
            latestVersion: data['app_version']?.toString() ?? '1.0.0',
            minVersion: data['min_app_version']?.toString() ?? '1.0.0',
            forceUpdate: isForce,
            updateTitle: data['update_title']?.toString() ?? 'New Version Available!',
            updateMessage: data['update_message']?.toString() ?? config.updateMessage,
            apkUrl: data['apk_url']?.toString() ?? '',
          );
        }
      }

      // Server responded but the verify endpoint returned non-200
      // (e.g. 404 means plugin is deactivated) — mark as NOT active
      debugPrint('Verification endpoint returned status: ${response.statusCode}');
      return VerificationResult(
        isActive: false,
        latestVersion: '1.0.0',
        minVersion: '1.0.0',
        forceUpdate: false,
        updateTitle: '',
        updateMessage: '',
        apkUrl: '',
      );

    } on TimeoutException {
      // Timeout — server is slow, allow app to work
      debugPrint('Verification timed out, allowing app to continue');
      return VerificationResult(
        isActive: true,
        latestVersion: '1.0.0',
        minVersion: '1.0.0',
        forceUpdate: false,
        updateTitle: '',
        updateMessage: '',
        apkUrl: '',
      );
    } catch (e) {
      // Network error (no internet, DNS failure, etc.)
      debugPrint('Verification network error: $e');
      return VerificationResult(
        isActive: true,
        latestVersion: '1.0.0',
        minVersion: '1.0.0',
        forceUpdate: false,
        updateTitle: '',
        updateMessage: '',
        apkUrl: '',
      );
    }
  }
}
