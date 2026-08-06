import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_links/app_links.dart';
import '../config/app_config.dart';
import '../services/verification_service.dart';
import '../services/push_service.dart';
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
  bool _isLoading = true;
  Timer? _verificationTimer;
  DateTime? currentBackPressTime;
  int _currentTabIndex = 0;
  bool _isOffline = false;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<String>? _pushSubscription;
  String? _lastFailedUrl;
  bool _isVerificationFailed = false;

  @override
  void initState() {
    super.initState();

    if (widget.config.pullRefresh == 'yes') {
      pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: AppConfig.hexToColor(widget.config.pullRefreshColor),
        ),
        onRefresh: () async {
          webViewController?.reload();
        },
      );
    }

    _verificationTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      final verificationService = VerificationService(widget.config);
      final result = await verificationService.verify();
      if (!result.isActive && mounted) {
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

    _checkConnectivity();
    _initDeepLinks();
    _setupPushDeepLinking();
  }

  void _setupPushDeepLinking() {
    _pushSubscription = pushService.onLaunchUrl.listen((String url) {
      if (webViewController != null && mounted) {
        webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      }
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("Failed to get initial deep link");
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint("Failed to handle deep link: $err");
    });
  }

  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    final siteUri = Uri.parse(widget.config.siteUrl);
    if (uri.host == siteUri.host || uri.scheme.startsWith('appreso')) {
       webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      setState(() {
        _isOffline = true;
      });
    }

    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (mounted) {
        setState(() {
          _isOffline = result == ConnectivityResult.none;
        });
        if (!_isOffline) {
          webViewController?.reload();
        }
      }
    });
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    _linkSubscription?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  void _handleError(String? url, int? code, String? description) {
    if (!mounted) return;
    _finishLoading();
    setState(() {
      _isVerificationFailed = true;
      _lastFailedUrl = url;
    });
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

        final now = DateTime.now();
        if (currentBackPressTime == null || 
            now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
          currentBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Press back again to exit"), duration: Duration(seconds: 2)),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppConfig.hexToColor(widget.config.preloaderBgColor),
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(pushService.consumePendingUrl() ?? widget.config.siteUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  cacheMode: (widget.config.offlineMode == 'yes' && _isOffline) 
                      ? CacheMode.LOAD_CACHE_ELSE_NETWORK 
                      : CacheMode.LOAD_DEFAULT,
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
                    _isVerificationFailed = false;
                    if (widget.config.preloaderEnabled == 'yes') {
                      _isLoading = true;
                    }
                  });
                },
                onLoadStop: (controller, url) async {
                  _finishLoading();
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100;
                  });
                  if (progress == 100) {
                    _finishLoading();
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true) {
                    _handleError(request.url?.toString(), error.type.toNativeValue(), error.description);
                  }
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  if (request.isForMainFrame == true && (errorResponse.statusCode ?? 0) >= 500) {
                    _handleError(request.url?.toString(), errorResponse.statusCode, errorResponse.reasonPhrase);
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  var uri = navigationAction.request.url!;
                  var siteUri = Uri.parse(widget.config.siteUrl);

                  if (uri.host != siteUri.host && uri.scheme.startsWith("http")) {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              
              if (widget.config.preloaderEnabled != 'yes' && _progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppConfig.hexToColor(widget.config.preloaderColor),
                    ),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                
              if (widget.config.preloaderEnabled == 'yes')
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_isLoading,
                    child: AnimatedOpacity(
                      opacity: _isLoading ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: Container(
                        color: AppConfig.hexToColor(widget.config.preloaderBgColor),
                        child: Center(
                          child: PreloaderAnimation(
                            style: widget.config.preloaderStyle,
                            color: AppConfig.hexToColor(widget.config.preloaderColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (_isVerificationFailed)
                Positioned.fill(
                  child: Container(
                    color: Colors.white,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                              'Failed to load page',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please check your internet connection and try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isVerificationFailed = false;
                                  _isLoading = true;
                                });
                                final retryUrl = _lastFailedUrl ?? widget.config.siteUrl;
                                webViewController?.loadUrl(
                                  urlRequest: URLRequest(url: WebUri(retryUrl)),
                                );
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366f1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
              if (widget.config.showBranding == 'yes')
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

class PreloaderAnimation extends StatefulWidget {
  final String style;
  final Color color;

  const PreloaderAnimation({super.key, required this.style, required this.color});

  @override
  State<PreloaderAnimation> createState() => _PreloaderAnimationState();
}

class _PreloaderAnimationState extends State<PreloaderAnimation> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.style) {
      case 'dots':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = index * 0.2;
                var value = (_controller.value - delay) % 1.0;
                if (value < 0) value += 1.0;
                final scale = math.sin(value * math.pi) * 0.5 + 0.5;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        );
      case 'progress':
        return SizedBox(
          width: 150,
          child: LinearProgressIndicator(color: widget.color),
        );
      case 'wave':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = index * 0.1;
                var value = (_controller.value - delay) % 1.0;
                if (value < 0) value += 1.0;
                final height = math.sin(value * math.pi) * 20 + 10;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 6,
                  height: height,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            );
          }),
        );
      case 'bounce':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = index * 0.2;
                var value = (_controller.value - delay) % 1.0;
                if (value < 0) value += 1.0;
                final dy = math.sin(value * math.pi) * -20;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        );
      case 'circular':
      default:
        return CircularProgressIndicator(color: widget.color);
    }
  }
}
