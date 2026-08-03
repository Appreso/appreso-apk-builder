import 'dart:convert';
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
      final response = await http.get(
        Uri.parse(config.verifyUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AppReso-Android/1.0',
        },
      ).timeout(const Duration(seconds: 10));

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
      return VerificationResult(isActive: false, requiredVersion: '1.0.0', updateMessage: '');
    } catch (e) {
      // Return true for isActive on network error so we don't lock them out if offline
      // unless we strictly want to require internet. Since we are adding offline mode,
      // it's better to allow them through if there's a network error.
      return VerificationResult(isActive: true, requiredVersion: '1.0.0', updateMessage: '');
    }
  }
}
