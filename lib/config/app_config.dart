import 'dart:convert';
import 'package:flutter/services.dart';

class AppConfig {
  final String siteUrl;
  final String appName;
  final String apiNamespace;

  const AppConfig({
    required this.siteUrl,
    required this.appName,
    required this.apiNamespace,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      siteUrl: json['site_url'] as String,
      appName: json['app_name'] as String,
      apiNamespace: json['api_namespace'] as String,
    );
  }

  static Future<AppConfig> load() async {
    final jsonString = await rootBundle.loadString('assets/config.json');
    final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    return AppConfig.fromJson(jsonMap);
  }

  String get verifyUrl => '$siteUrl/wp-json/$apiNamespace/verify';
  String get siteInfoUrl => '$siteUrl/wp-json/$apiNamespace/site-info';
}
