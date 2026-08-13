import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class VerificationResult {
  final bool isActive;
  final String requiredVersion;
  final String updateMessage;

  VerificationResult({
    required this.isActive,
    required this.requiredVersion,
    required this.updateMessage,
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
          return VerificationResult(
            isActive: data['active'] == true,
            requiredVersion: data['app_version'] ?? '1.0.0',
            updateMessage: data['update_message'] ?? config.updateMessage,
          );
        }
      }

      // Server responded but the verify endpoint returned non-200
      // (e.g. 404 means plugin is deactivated) — mark as NOT active
      debugPrint('Verification endpoint returned status: ${response.statusCode}');
      return VerificationResult(isActive: false, requiredVersion: '1.0.0', updateMessage: '');

    } on TimeoutException {
      // Timeout — server is slow, allow app to work
      debugPrint('Verification timed out, allowing app to continue');
      return VerificationResult(isActive: true, requiredVersion: '1.0.0', updateMessage: '');
    } catch (e) {
      // Network error (no internet, DNS failure, etc.)
      // Can't reach server at all — allow app to work offline
      debugPrint('Verification network error: $e');
      return VerificationResult(isActive: true, requiredVersion: '1.0.0', updateMessage: '');
    }
  }
}
