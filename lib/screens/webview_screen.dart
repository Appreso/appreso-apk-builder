import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/verification_service.dart';
import '../widgets/powered_by_badge.dart';
import 'error_screen.dart';

class WebViewScreen extends StatefulWidget {
  final AppConfig config;

  const WebViewScreen({super.key, required this.config});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  double _progress = 0;
  Timer? _verificationTimer;
  DateTime? currentBackPressTime;

  @override
  void initState() {
    super.initState();

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFF6366f1)),
      onRefresh: () async {
        webViewController?.reload();
      },
    );

    // Periodic verification every 30 minutes
    _verificationTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      final verificationService = VerificationService(widget.config);
      final isVerified = await verificationService.verify();
      if (!isVerified && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ErrorScreen(
              config: widget.config,
              errorMessage: 'Verification failed. The site might be down or the plugin was deactivated.',
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final controller = webViewController;
        if (controller != null && await controller.canGoBack()) {
          controller.goBack();
          return;
        }

        final now = DateTime.now();
        if (currentBackPressTime == null || 
            now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
          currentBackPressTime = now;
          _showToast("Press back again to exit");
        } else {
          // Allow exit
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.config.siteUrl)),
                initialSettings: InAppWebViewSettings(
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
                ),
                pullToRefreshController: pullToRefreshController,
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _progress = 0;
                  });
                },
                onLoadStop: (controller, url) async {
                  pullToRefreshController?.endRefreshing();
                  setState(() {
                    _progress = 1.0;
                  });
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100;
                  });
                },
                onReceivedError: (controller, request, error) {
                  pullToRefreshController?.endRefreshing();
                  if (request.isForMainFrame == true) {
                    _showToast("Failed to load: ${error.description}");
                  }
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  pullToRefreshController?.endRefreshing();
                  if (request.isForMainFrame == true) {
                    _showToast("HTTP Error: ${errorResponse.statusCode}");
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  var uri = navigationAction.request.url!;
                  var siteUri = Uri.parse(widget.config.siteUrl);

                  if (uri.host != siteUri.host && uri.scheme.startsWith("http")) {
                    // External link
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              if (_progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    color: const Color(0xFF6366f1),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              const Positioned(
                bottom: 8,
                right: 8,
                child: PoweredByBadge(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
