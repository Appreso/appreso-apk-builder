import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class VerificationService {
  final AppConfig config;

  const VerificationService(this.config);

  Future<bool> verify() async {
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
        if (data != null && data['active'] == true) {
          return true;
        }
      }
      return false;
    } catch (e) {
      // Handle network errors, timeouts, and JSON parsing errors gracefully
      return false;
    }
  }
}
