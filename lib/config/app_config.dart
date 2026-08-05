import 'dart:convert';
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
    return AppConfig(
      siteUrl: json['site_url'] as String? ?? 'https://example.com',
      appName: json['app_name'] as String? ?? 'AppReso App',
      apiNamespace: json['api_namespace'] as String? ?? 'appreso/v1',
      splashType: json['splash_type'] ?? 'color',
      splashBgColor: json['splash_bg_color'] ?? '#6366f1',
      splashShowName: json['splash_show_name'] ?? 'yes',
      splashCustomText: json['splash_custom_text'] ?? '',
      splashTextColor: json['splash_text_color'] ?? '#ffffff',
      preloaderEnabled: json['preloader_enabled'] as String? ?? 'yes',
      preloaderStyle: json['preloader_style'] as String? ?? 'circular',
      preloaderColor: json['preloader_color'] as String? ?? '#6366f1',
      preloaderBgColor: json['preloader_bg_color'] as String? ?? '#ffffff',
      pullRefresh: json['pull_refresh'] as String? ?? 'yes',
      pullRefreshColor: json['pull_refresh_color'] as String? ?? '#6366f1',
      statusBarColor: json['status_bar_color'] as String? ?? '#6366f1',
      showBranding: json['show_branding'] as String? ?? 'yes',
      offlineMode: json['offline_mode'] as String? ?? 'yes',
      appVersion: json['app_version'] as String? ?? '1.0.0',
      updateMessage: json['update_message'] as String? ?? 'A new version of the app is available. Please update to continue.',
      onesignalAppId: json['onesignal_app_id'] as String? ?? '',
      deepLinkUrl: json['deep_link_url'] as String? ?? '',
      bottomNavEnabled: json['bottom_nav_enabled'] == 'yes',
      bottomNavTabs: json['bottom_nav_tabs'] ?? [],
      bottomNavBgColor: json['bottom_nav_bg_color'] ?? '#ffffff',
      bottomNavActiveColor: json['bottom_nav_active_color'] ?? '#6366f1',
      bottomNavInactiveColor: json['bottom_nav_inactive_color'] ?? '#94a3b8',
      bottomNavStyle: json['bottom_nav_style'] ?? 'full',
    );
  }

  static Color hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  static Future<AppConfig> load() async {
    final jsonString = await rootBundle.loadString('assets/config.json');
    final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    return AppConfig.fromJson(jsonMap);
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
