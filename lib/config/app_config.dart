import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppConfig {
  final String siteUrl;
  final String appName;
  final String apiNamespace;

  // Splash Screen
  final String splashType; // 'color' or 'image'
  final String splashBgColor;
  final String splashShowName; // 'yes' or 'no'
  final String splashCustomText;
  final String splashTextColor;
  
  // Preloader
  final String preloaderEnabled; // 'yes' or 'no'
  final String preloaderStyle; // 'circular', 'dots', 'progress', 'wave', 'bounce'
  final String preloaderColor;
  final String preloaderBgColor;
  
  // Navigation & UI
  final String pullRefresh; // 'yes' or 'no'
  final String pullRefreshColor;
  final String statusBarColor;
  final String showBranding; // 'yes' or 'no'

  // Phase 1 Features
  final String offlineMode; // 'yes' or 'no'
  final String appVersion;
  final String updateMessage;
  final String onesignalAppId;
  final String deepLinkUrl;
  final bool bottomNavEnabled;
  final List<dynamic> bottomNavTabs;
  final String bottomNavBgColor;
  final String bottomNavActiveColor;
  final String bottomNavInactiveColor;
  final String bottomNavStyle;

  const AppConfig({
    required this.siteUrl,
    required this.appName,
    required this.apiNamespace,
    required this.splashType,
    required this.splashBgColor,
    required this.splashShowName,
    required this.splashCustomText,
    required this.splashTextColor,
    required this.preloaderEnabled,
    required this.preloaderStyle,
    required this.preloaderColor,
    required this.preloaderBgColor,
    required this.pullRefresh,
    required this.pullRefreshColor,
    required this.statusBarColor,
    required this.showBranding,
    required this.offlineMode,
    required this.appVersion,
    required this.updateMessage,
    required this.onesignalAppId,
    required this.deepLinkUrl,
    required this.bottomNavEnabled,
    required this.bottomNavTabs,
    required this.bottomNavBgColor,
    required this.bottomNavActiveColor,
    required this.bottomNavInactiveColor,
    required this.bottomNavStyle,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    List<dynamic> parsedTabs = [];
    if (json['bottom_nav_tabs'] != null) {
      if (json['bottom_nav_tabs'] is List) {
        parsedTabs = json['bottom_nav_tabs'] as List<dynamic>;
      } else if (json['bottom_nav_tabs'] is String) {
        try {
          final decoded = jsonDecode(json['bottom_nav_tabs'] as String);
          if (decoded is List) {
            parsedTabs = decoded;
          }
        } catch (_) {}
      }
    }

    return AppConfig(
      siteUrl: (json['site_url'] as String?)?.isNotEmpty == true ? json['site_url'] as String : 'https://example.com',
      appName: (json['app_name'] as String?)?.isNotEmpty == true ? json['app_name'] as String : 'AppReso App',
      apiNamespace: (json['api_namespace'] as String?)?.isNotEmpty == true ? json['api_namespace'] as String : 'appreso/v1',
      splashType: json['splash_type']?.toString() ?? 'color',
      splashBgColor: json['splash_bg_color']?.toString() ?? '#6366f1',
      splashShowName: json['splash_show_name']?.toString() ?? 'yes',
      splashCustomText: json['splash_custom_text']?.toString() ?? '',
      splashTextColor: json['splash_text_color']?.toString() ?? '#ffffff',
      preloaderEnabled: json['preloader_enabled']?.toString() ?? 'yes',
      preloaderStyle: json['preloader_style']?.toString() ?? 'circular',
      preloaderColor: json['preloader_color']?.toString() ?? '#6366f1',
      preloaderBgColor: json['preloader_bg_color']?.toString() ?? '#ffffff',
      pullRefresh: json['pull_refresh']?.toString() ?? 'yes',
      pullRefreshColor: json['pull_refresh_color']?.toString() ?? '#6366f1',
      statusBarColor: json['status_bar_color']?.toString() ?? '#6366f1',
      showBranding: json['show_branding']?.toString() ?? 'yes',
      offlineMode: json['offline_mode']?.toString() ?? 'yes',
      appVersion: json['app_version']?.toString() ?? '1.0.0',
      updateMessage: json['update_message']?.toString() ?? 'A new version of the app is available. Please update to continue.',
      onesignalAppId: json['onesignal_app_id']?.toString() ?? '',
      deepLinkUrl: json['deep_link_url']?.toString() ?? '',
      bottomNavEnabled: json['bottom_nav_enabled']?.toString() == 'yes',
      bottomNavTabs: parsedTabs,
      bottomNavBgColor: json['bottom_nav_bg_color']?.toString() ?? '#ffffff',
      bottomNavActiveColor: json['bottom_nav_active_color']?.toString() ?? '#6366f1',
      bottomNavInactiveColor: json['bottom_nav_inactive_color']?.toString() ?? '#94a3b8',
      bottomNavStyle: json['bottom_nav_style']?.toString() ?? 'full',
    );
  }

  static Color hexToColor(String hex) {
    try {
      hex = hex.replaceAll('#', '').trim();
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF6366f1);
  }

  static AppConfig defaultConfig() {
    return const AppConfig(
      siteUrl: 'https://example.com',
      appName: 'AppReso App',
      apiNamespace: 'appreso/v1',
      splashType: 'color',
      splashBgColor: '#6366f1',
      splashShowName: 'yes',
      splashCustomText: '',
      splashTextColor: '#ffffff',
      preloaderEnabled: 'yes',
      preloaderStyle: 'circular',
      preloaderColor: '#6366f1',
      preloaderBgColor: '#ffffff',
      pullRefresh: 'yes',
      pullRefreshColor: '#6366f1',
      statusBarColor: '#6366f1',
      showBranding: 'yes',
      offlineMode: 'yes',
      appVersion: '1.0.0',
      updateMessage: 'A new version of the app is available.',
      onesignalAppId: '',
      deepLinkUrl: '',
      bottomNavEnabled: false,
      bottomNavTabs: [],
      bottomNavBgColor: '#ffffff',
      bottomNavActiveColor: '#6366f1',
      bottomNavInactiveColor: '#94a3b8',
      bottomNavStyle: 'full',
    );
  }

  static Future<AppConfig> load() async {
    try {
      final jsonString = await rootBundle.loadString('assets/config.json');
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return AppConfig.fromJson(jsonMap);
    } catch (e) {
      return defaultConfig();
    }
  }

  String get verifyUrl {
    final cleanUrl = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    return '$cleanUrl/index.php?rest_route=/$apiNamespace/verify';
  }

  String get siteInfoUrl {
    final cleanUrl = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    return '$cleanUrl/index.php?rest_route=/$apiNamespace/site-info';
  }

  String get analyticsUrl {
    final cleanUrl = siteUrl.endsWith('/') ? siteUrl.substring(0, siteUrl.length - 1) : siteUrl;
    return '$cleanUrl/index.php?rest_route=/$apiNamespace/analytics/event';
  }
}
