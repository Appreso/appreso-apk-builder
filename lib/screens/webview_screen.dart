import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/verification_service.dart';
import '../services/push_service.dart';
import 'error_screen.dart';

class WebViewScreen extends StatefulWidget {
  final AppConfig config;

  const WebViewScreen({super.key, required this.config});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  
  double _progress = 0;
  bool _isLoading = true;
  Timer? _verificationTimer;
  String? _lastFailedUrl;
  bool _isVerificationFailed = false;

  late InAppWebViewSettings settings;

  @override
  void initState() {
    super.initState();
    
    settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      cacheMode: CacheMode.LOAD_DEFAULT,
      allowFileAccess: true,
      allowContentAccess: true,
      supportZoom: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      userAgent: 'AppReso/${widget.config.appName} Android',
      transparentBackground: true,
      allowsInlineMediaPlayback: true,
    );

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: AppConfig.hexToColor(widget.config.primaryColor),
      ),
      onRefresh: () async {
        if (kIsWeb) return;
        webViewController?.reload();
      },
    );

    _setupVerificationTimer();
    _setupPushDeepLinking();
  }
  
  void _setupPushDeepLinking() {
    // Listen for URLs coming from push notifications
    PushService.onLaunchUrl = (String url) {
      if (webViewController != null && mounted) {
        webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      }
    };
  }

  void _setupVerificationTimer() {
    _verificationTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      final verificationService = VerificationService(widget.config);
      final isVerified = await verificationService.verify();
      
      if (!isVerified && mounted && !_isVerificationFailed) {
        setState(() {
          _isVerificationFailed = true;
        });
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ErrorScreen(config: widget.config),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    PushService.onLaunchUrl = null;
    super.dispose();
  }

  Future<void> _handleError(String? url, int? code, String? message) async {
    if (url != null && !url.startsWith('http')) return;
    
    setState(() {
      _isLoading = false;
      _lastFailedUrl = url;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection error. Please check your internet.'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              if (_lastFailedUrl != null && webViewController != null) {
                webViewController!.loadUrl(
                  urlRequest: URLRequest(url: WebUri(_lastFailedUrl!)),
                );
              } else {
                webViewController?.reload();
              }
            },
          ),
          duration: const Duration(days: 1), 
        ),
      );
    }
  }

  void _finishLoading() {
    pullToRefreshController?.endRefreshing();
    setState(() {
      _progress = 1.0;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusBarColor = AppConfig.hexToColor(widget.config.statusBarColor);
    final isDark = statusBarColor.computeLuminance() < 0.5;
    
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: statusBarColor,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final controller = webViewController;
        if (controller != null && await controller.canGoBack()) {
          controller.goBack();
          return;
        }
        
        // Let system handle exit if we can't go back
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppConfig.hexToColor(widget.config.splashBgColor),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              InAppWebView(
                key: webViewKey,
                initialUrlRequest: URLRequest(url: WebUri(widget.config.siteUrl)),
                initialSettings: settings,
                pullToRefreshController: pullToRefreshController,
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  
                  // Setup deep linking hook for initially opened links via intents
                  _setupInitialDeepLink(controller);
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    _progress = 0.1;
                  });
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  var uri = navigationAction.request.url;
                  
                  if (uri == null) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  if (!uri.scheme.startsWith("http")) {
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                        return NavigationActionPolicy.CANCEL;
                      }
                    } catch (e) {
                      debugPrint('Error launching intent: $e');
                    }
                  }
                  
                  // Handle target="_blank" or external links (basic logic)
                  if (uri.host != WebUri(widget.config.siteUrl).host && uri.host.isNotEmpty) {
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      return NavigationActionPolicy.CANCEL;
                    } catch (e) {
                      debugPrint('Error launching external URL: $e');
                    }
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStop: (controller, url) async {
                  _finishLoading();
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame) {
                    _handleError(request.url?.toString(), error.type.toNativeValue(), error.description);
                  }
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  if (request.isForMainFrame && errorResponse.statusCode >= 500) {
                    _handleError(request.url?.toString(), errorResponse.statusCode, errorResponse.reasonPhrase);
                  }
                },
                onProgressChanged: (controller, progress) {
                  if (progress == 100) {
                    _finishLoading();
                  } else {
                    setState(() {
                      _progress = progress / 100;
                    });
                  }
                },
              ),
              
              if (_isLoading && _progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppConfig.hexToColor(widget.config.primaryColor),
                    ),
                    minHeight: 3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _setupInitialDeepLink(InAppWebViewController controller) async {
    // Basic intent check logic can be added here if using uni_links package.
    // For now, Android 12+ verified app links load standardly into the app.
  }
}
