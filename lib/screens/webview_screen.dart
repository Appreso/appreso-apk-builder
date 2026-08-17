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
  bool _isNavBarVisible = true;
  int _lastScrollY = 0;

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

    // Periodic verification every 30 minutes
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
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        setState(() {
          _isOffline = true;
          _isVerificationFailed = true;
          _isLoading = false;
        });
      }

      Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
        if (mounted) {
          setState(() {
            _isOffline = result == ConnectivityResult.none;
            if (!_isOffline && _isVerificationFailed) {
              _isVerificationFailed = false;
              _isLoading = true;
              final retryUrl = _lastFailedUrl ?? widget.config.siteUrl;
              webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(retryUrl)),
              );
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
    }
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    _linkSubscription?.cancel();
    _pushSubscription?.cancel();
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
          _showToast("Press back again to exit");
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
                onScrollChanged: (controller, x, y) {
                  if (widget.config.bottomNavHideOnScroll == 'yes') {
                    if (y > _lastScrollY + 10 && _isNavBarVisible) {
                      setState(() => _isNavBarVisible = false);
                    } else if (y < _lastScrollY - 10 && !_isNavBarVisible) {
                      setState(() => _isNavBarVisible = true);
                    }
                    _lastScrollY = y;
                  }
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
                  final isMainFrame = request.isForMainFrame ?? true;
                  if (isMainFrame) {
                    _handleError(request.url?.toString(), error.type.toNativeValue(), error.description);
                  }
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  final isMainFrame = request.isForMainFrame ?? true;
                  if (isMainFrame && (errorResponse.statusCode ?? 0) >= 500) {
                    _handleError(request.url?.toString(), errorResponse.statusCode, errorResponse.reasonPhrase);
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;

                  var siteUri = Uri.parse(widget.config.siteUrl);

                  bool isSameDomain = uri.host == siteUri.host ||
                      uri.host.endsWith('.${siteUri.host}') ||
                      siteUri.host.endsWith('.${uri.host}');

                  if (!isSameDomain && uri.scheme.startsWith("http")) {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  
                  return NavigationActionPolicy.ALLOW;
                },
              ),
              
              // Navigation Bar overlay (Positioned in Stack for true floating margins)
              if (widget.config.bottomNavEnabled && widget.config.bottomNavTabs.isNotEmpty)
                _buildPositionedNavigationBar(),
                
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
                        child: Align(
                          alignment: widget.config.preloaderPosition == 'top'
                              ? Alignment.topCenter
                              : widget.config.preloaderPosition == 'bottom'
                                  ? Alignment.bottomCenter
                                  : Alignment.center,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: widget.config.preloaderPosition == 'top' ? 80 : 0,
                              bottom: widget.config.preloaderPosition == 'bottom' ? 80 : 0,
                            ),
                            child: PreloaderAnimation(
                              style: widget.config.preloaderStyle,
                              color: AppConfig.hexToColor(widget.config.preloaderColor),
                              size: widget.config.preloaderSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Error Retry Overlay
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

  Widget _buildPositionedNavigationBar() {
    final isTop = widget.config.bottomNavPosition == 'top';
    final isFloating = widget.config.bottomNavStyle == 'floating';
    final marginLeft = isFloating ? widget.config.bottomNavMarginLeft : 0.0;
    final marginRight = isFloating ? widget.config.bottomNavMarginRight : 0.0;
    final marginEdge = isFloating ? widget.config.bottomNavMarginBottom : 0.0;

    return Positioned(
      top: isTop ? marginEdge : null,
      bottom: !isTop ? marginEdge : null,
      left: marginLeft,
      right: marginRight,
      child: _buildNavigationBarContent(),
    );
  }

  Widget _buildNavigationBarContent() {
    final tabs = widget.config.bottomNavTabs;
    final bgColor = AppConfig.hexToColor(widget.config.bottomNavBgColor);
    final activeColor = AppConfig.hexToColor(widget.config.bottomNavActiveColor);
    final inactiveColor = AppConfig.hexToColor(widget.config.bottomNavInactiveColor);
    final showLabels = widget.config.bottomNavShowLabels == 'yes';
    final iconSize = widget.config.bottomNavIconSize;
    final isFloating = widget.config.bottomNavStyle == 'floating';
    final borderRadius = isFloating ? widget.config.bottomNavBorderRadius : 0.0;
    final hasShadow = widget.config.bottomNavShadow == 'yes';
    final elevation = widget.config.bottomNavElevation;
    final paddingY = widget.config.bottomNavPaddingY;
    final paddingX = widget.config.bottomNavPaddingX;
    final borderWidth = widget.config.bottomNavBorderWidth;
    final borderColor = AppConfig.hexToColor(widget.config.bottomNavBorderColor);
    final indicatorStyle = widget.config.bottomNavIndicatorStyle;

    Widget navItems = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderWidth > 0 ? Border.all(color: borderColor, width: borderWidth) : null,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: elevation * 2,
                  offset: Offset(0, isFloating ? elevation / 2 : -elevation / 3),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: paddingY, horizontal: paddingX),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(tabs.length, (index) {
                final tab = tabs[index];
                final isSelected = _currentTabIndex == index;
                final itemColor = isSelected ? activeColor : inactiveColor;
                final iconName = tab['icon']?.toString() ?? 'admin-home';
                final label = tab['label']?.toString() ?? '';

                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(borderRadius > 0 ? borderRadius / 2 : 12),
                    onTap: () {
                      final subMenuRaw = tab['sub_menu'];
                      List<dynamic> subMenu = [];
                      if (subMenuRaw is List && subMenuRaw.isNotEmpty) {
                        subMenu = subMenuRaw;
                      }

                      if (subMenu.isNotEmpty) {
                        _showSubMenuBottomSheet(label, subMenu);
                      } else {
                        setState(() {
                          _currentTabIndex = index;
                        });
                        final url = tab['url'] as String? ?? '';
                        if (url.isNotEmpty) {
                          final targetUrl = Uri.parse(widget.config.siteUrl).resolve(url).toString();
                          webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
                        }
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: (indicatorStyle == 'pill' && isSelected) ? 8 : 2,
                      ),
                      decoration: (indicatorStyle == 'pill' && isSelected)
                          ? BoxDecoration(
                              color: activeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                            )
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getIconForString(iconName),
                            size: iconSize,
                            color: itemColor,
                          ),
                          if (indicatorStyle == 'dot' && isSelected) ...[
                            const SizedBox(height: 3),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: activeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          if (showLabels && label.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: itemColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    // Apply Hide on Scroll animation
    if (widget.config.bottomNavHideOnScroll == 'yes') {
      final slideOffset = widget.config.bottomNavPosition == 'top'
          ? (_isNavBarVisible ? Offset.zero : const Offset(0, -1.8))
          : (_isNavBarVisible ? Offset.zero : const Offset(0, 1.8));

      return AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        offset: slideOffset,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isNavBarVisible ? 1.0 : 0.0,
          child: navItems,
        ),
      );
    }

    return navItems;
  }

  void _showSubMenuBottomSheet(String title, List<dynamic> subMenu) {
    final bgColor = AppConfig.hexToColor(widget.config.submenuBgColor);
    final textColor = AppConfig.hexToColor(widget.config.submenuTextColor);
    final activeColor = AppConfig.hexToColor(widget.config.submenuActiveColor);
    final showIcons = widget.config.submenuShowIcons == 'yes';
    final showHeader = widget.config.submenuShowHeader == 'yes';
    final isGrid = widget.config.submenuStyle == 'grid';
    final columns = widget.config.submenuColumns.clamp(2, 4);
    final borderRadius = widget.config.submenuBorderRadius;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        Widget content;

        if (isGrid) {
          content = GridView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 4 ? 0.85 : 0.95,
            ),
            itemCount: subMenu.length,
            itemBuilder: (context, i) {
              final item = subMenu[i];
              final itemLabel = item['label']?.toString() ?? '';
              final itemIcon = item['icon']?.toString() ?? 'arrow-right-alt2';
              final itemUrl = item['url']?.toString() ?? '';

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    if (itemUrl.isNotEmpty) {
                      final targetUrl = Uri.parse(widget.config.siteUrl).resolve(itemUrl).toString();
                      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: activeColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: activeColor.withOpacity(0.12)),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showIcons) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: activeColor.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getIconForString(itemIcon), color: activeColor, size: 24),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          itemLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        } else {
          content = ListView.separated(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: subMenu.length,
            separatorBuilder: (_, __) => Divider(color: Colors.grey.withOpacity(0.15), height: 1),
            itemBuilder: (context, i) {
              final item = subMenu[i];
              final itemLabel = item['label']?.toString() ?? '';
              final itemIcon = item['icon']?.toString() ?? 'arrow-right-alt2';
              final itemUrl = item['url']?.toString() ?? '';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: showIcons
                    ? Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: activeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_getIconForString(itemIcon), color: activeColor, size: 20),
                      )
                    : null,
                title: Text(
                  itemLabel,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Icon(Icons.arrow_forward_ios_rounded, color: textColor.withOpacity(0.4), size: 14),
                onTap: () {
                  Navigator.pop(context);
                  if (itemUrl.isNotEmpty) {
                    final targetUrl = Uri.parse(widget.config.siteUrl).resolve(itemUrl).toString();
                    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
                  }
                },
              );
            },
          );
        }

        double? fixedHeight;
        if (widget.config.submenuHeight == 'half') {
          fixedHeight = MediaQuery.of(context).size.height * 0.5;
        } else if (widget.config.submenuHeight == 'large') {
          fixedHeight = MediaQuery.of(context).size.height * 0.75;
        }

        return SafeArea(
          child: Container(
            height: fixedHeight,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: fixedHeight != null ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (showHeader && title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: textColor.withOpacity(0.6), size: 20),
                          onPressed: () => Navigator.pop(context),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                if (showHeader && title.isNotEmpty)
                  Divider(color: Colors.grey.withOpacity(0.15), height: 1),
                const SizedBox(height: 8),
                fixedHeight != null ? Expanded(child: content) : content,
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getIconForString(String rawIconName) {
    String name = rawIconName.toLowerCase().trim()
        .replaceAll('dashicons-', '')
        .replaceAll('dashicon-', '')
        .replaceAll('_', '-')
        .replaceAll(' ', '-');

    switch (name) {
      // Home & Main
      case 'admin-home':
      case 'home':
      case 'house':
        return Icons.home_rounded;
      
      // Search
      case 'search':
        return Icons.search_rounded;
      
      // Settings & Tools
      case 'admin-settings':
      case 'settings':
      case 'admin-generic':
      case 'admin-tools':
      case 'build':
        return Icons.settings_rounded;
      
      // Users & Accounts
      case 'admin-users':
      case 'businessman':
      case 'person':
      case 'account-circle':
      case 'groups':
      case 'group':
        return Icons.person_rounded;
      
      // Cart, Shop & Commerce
      case 'cart':
      case 'shopping-cart':
      case 'shopping-bag':
      case 'store':
      case 'storefront':
        return Icons.shopping_cart_rounded;
      case 'sell':
      case 'local-offer':
      case 'tickets':
      case 'tickets-alt':
        return Icons.local_offer_rounded;
      case 'payment':
      case 'credit-card':
      case 'account-balance':
      case 'monetization-on':
        return Icons.credit_card_rounded;
      
      // Favorites & Ratings
      case 'heart':
      case 'favorite':
        return Icons.favorite_rounded;
      case 'star':
      case 'star-filled':
      case 'star-empty':
      case 'awards':
        return Icons.star_rounded;
      case 'thumbs-up':
      case 'thumb-up':
        return Icons.thumb_up_rounded;
      case 'thumbs-down':
      case 'thumb-down':
        return Icons.thumb_down_rounded;
      
      // Notifications & Chat
      case 'bell':
      case 'notifications':
        return Icons.notifications_rounded;
      case 'email':
      case 'mail':
      case 'format-email':
        return Icons.email_rounded;
      case 'chat':
      case 'format-chat':
      case 'format-status':
        return Icons.chat_bubble_rounded;
      case 'smartphone':
      case 'phone':
        return Icons.phone_android_rounded;
      
      // Media & Documents
      case 'camera':
      case 'camera-alt':
        return Icons.camera_alt_rounded;
      case 'image':
      case 'format-image':
        return Icons.image_rounded;
      case 'movie':
      case 'format-video':
      case 'video-alt3':
      case 'videocam':
        return Icons.videocam_rounded;
      case 'music-note':
      case 'playlist-audio':
      case 'controls-volumeon':
        return Icons.music_note_rounded;
      case 'article':
      case 'media-document':
      case 'media-text':
      case 'description':
      case 'clipboard':
        return Icons.description_rounded;
      
      // Navigation & Layout
      case 'menu':
      case 'menu-alt':
      case 'menu-alt2':
      case 'menu-alt3':
        return Icons.menu_rounded;
      case 'grid-view':
      case 'list-view':
      case 'category':
      case 'list':
        return Icons.grid_view_rounded;
      case 'location':
      case 'location-alt':
      case 'place':
      case 'map':
        return Icons.location_on_rounded;
      case 'dashboard':
      case 'admin-site':
      case 'admin-site-alt3':
        return Icons.dashboard_rounded;
      
      // Arrows & Navigation
      case 'arrow-left-alt2':
      case 'arrow-left':
      case 'arrow-back':
        return Icons.arrow_back_rounded;
      case 'arrow-right-alt2':
      case 'arrow-right':
      case 'arrow-forward':
        return Icons.arrow_forward_rounded;
      case 'arrow-up-alt2':
      case 'arrow-up':
        return Icons.arrow_upward_rounded;
      case 'arrow-down-alt2':
      case 'arrow-down':
        return Icons.arrow_downward_rounded;
      
      // Travel & Buildings
      case 'car':
      case 'directions-car':
      case 'airport-shuttle':
        return Icons.directions_car_rounded;
      case 'airplane':
      case 'flight':
        return Icons.flight_rounded;
      case 'building':
      case 'apartment':
        return Icons.apartment_rounded;
      case 'food':
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'local-hospital':
        return Icons.local_hospital_rounded;
      case 'school':
        return Icons.school_rounded;
      
      // Info, Warnings & Status
      case 'info':
      case 'info-outline':
        return Icons.info_rounded;
      case 'warning':
      case 'sos':
      case 'error':
        return Icons.warning_amber_rounded;
      case 'yes':
      case 'check':
        return Icons.check_circle_rounded;
      case 'no':
      case 'close':
        return Icons.cancel_rounded;
      case 'plus':
      case 'plus-alt':
      case 'add':
        return Icons.add_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'trash':
      case 'delete':
        return Icons.delete_rounded;
      case 'share':
      case 'share-alt':
        return Icons.share_rounded;
      case 'lock':
        return Icons.lock_rounded;
      case 'unlock':
        return Icons.lock_open_rounded;
      case 'shield':
      case 'security':
        return Icons.shield_rounded;
      case 'wifi':
        return Icons.wifi_rounded;
      case 'lightbulb':
        return Icons.lightbulb_rounded;
      case 'paperclip':
      case 'attach-file':
        return Icons.attach_file_rounded;
      case 'microphone':
      case 'mic':
        return Icons.mic_rounded;
      case 'calendar-alt':
      case 'calendar':
      case 'event':
        return Icons.calendar_today_rounded;
      case 'analytics':
      case 'bar-chart':
      case 'trending-up':
        return Icons.analytics_rounded;
      case 'sports-esports':
      case 'games':
        return Icons.sports_esports_rounded;
      case 'rss':
        return Icons.rss_feed_rounded;
      case 'cloud':
        return Icons.cloud_rounded;
      case 'rocket-launch':
      case 'controls-play':
        return Icons.play_arrow_rounded;
      
      default:
        return Icons.circle;
    }
  }
}

class PreloaderAnimation extends StatefulWidget {
  final String style;
  final Color color;
  final String size;

  const PreloaderAnimation({super.key, required this.style, required this.color, this.size = 'medium'});

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

  double _getSizeMultiplier() {
    switch (widget.size) {
      case 'small': return 0.6;
      case 'large': return 1.5;
      case 'medium':
      default: return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mult = _getSizeMultiplier();
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
                    margin: EdgeInsets.symmetric(horizontal: 4 * mult),
                    width: 12 * mult,
                    height: 12 * mult,
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
          width: 150 * mult,
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
                final height = math.sin(value * math.pi) * 20 * mult + 10 * mult;
                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 3 * mult),
                  width: 6 * mult,
                  height: height,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(3 * mult),
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
                final dy = math.sin(value * math.pi) * -20 * mult;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 6 * mult),
                    width: 16 * mult,
                    height: 16 * mult,
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
        return SizedBox(
          width: 40 * mult,
          height: 40 * mult,
          child: CircularProgressIndicator(color: widget.color, strokeWidth: 3 * mult),
        );
    }
  }
}
