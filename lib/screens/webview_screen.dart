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
              
              // Top-positioned navigation bar
              if (widget.config.bottomNavPosition == 'top' && widget.config.bottomNavEnabled && widget.config.bottomNavTabs.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomNavigationBar() ?? const SizedBox.shrink(),
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
        bottomNavigationBar: widget.config.bottomNavPosition != 'top' ? _buildBottomNavigationBar() : null,
      ),
    );
  }

  Widget? _buildBottomNavigationBar() {
    if (!widget.config.bottomNavEnabled || widget.config.bottomNavTabs.isEmpty) {
      return null;
    }

    final tabs = widget.config.bottomNavTabs;
    final bgColor = AppConfig.hexToColor(widget.config.bottomNavBgColor);
    final activeColor = AppConfig.hexToColor(widget.config.bottomNavActiveColor);
    final inactiveColor = AppConfig.hexToColor(widget.config.bottomNavInactiveColor);
    final showLabels = widget.config.bottomNavShowLabels == 'yes';
    final iconSize = widget.config.bottomNavIconSize;
    
    Widget navBar = BottomNavigationBar(
      currentIndex: _currentTabIndex,
      type: BottomNavigationBarType.fixed,
      backgroundColor: widget.config.bottomNavStyle == 'floating' ? Colors.transparent : bgColor,
      elevation: widget.config.bottomNavStyle == 'floating' ? 0 : (widget.config.bottomNavShadow == 'yes' ? widget.config.bottomNavElevation : 0),
      selectedItemColor: activeColor,
      unselectedItemColor: inactiveColor,
      showSelectedLabels: showLabels,
      showUnselectedLabels: showLabels,
      selectedFontSize: showLabels ? 12 : 0,
      unselectedFontSize: showLabels ? 12 : 0,
      iconSize: iconSize,
      onTap: (index) {
        final tab = tabs[index];
        final subMenuRaw = tab['sub_menu'];
        List<dynamic> subMenu = [];
        if (subMenuRaw is List && subMenuRaw.isNotEmpty) {
          subMenu = subMenuRaw;
        }

        if (subMenu.isNotEmpty) {
          _showSubMenuBottomSheet(tab['label']?.toString() ?? '', subMenu);
        } else {
          setState(() {
            _currentTabIndex = index;
          });
          final url = tabs[index]['url'] as String? ?? '';
          if (url.isNotEmpty) {
            final targetUrl = Uri.parse(widget.config.siteUrl).resolve(url).toString();
            webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(targetUrl)));
          }
        }
      },
      items: tabs.map<BottomNavigationBarItem>((tab) {
        return BottomNavigationBarItem(
          icon: Icon(_getIconForString(tab['icon']?.toString() ?? ''), size: iconSize),
          label: tab['label']?.toString() ?? '',
        );
      }).toList(),
    );

    if (widget.config.bottomNavStyle == 'floating') {
      final marginLeft = widget.config.bottomNavMarginLeft;
      final marginRight = widget.config.bottomNavMarginRight;
      final marginBottom = widget.config.bottomNavMarginBottom;
      final borderRadius = widget.config.bottomNavBorderRadius;
      final hasShadow = widget.config.bottomNavShadow == 'yes';
      final elevation = widget.config.bottomNavElevation;

      navBar = SafeArea(
        child: Container(
          margin: EdgeInsets.only(left: marginLeft, right: marginRight, bottom: marginBottom),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: hasShadow
                ? [
                    BoxShadow(
                      color: const Color.fromRGBO(0, 0, 0, 0.1),
                      blurRadius: elevation * 2.5,
                      offset: Offset(0, elevation / 2),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: navBar,
          ),
        ),
      );
    }

    if (widget.config.bottomNavHideOnScroll == 'yes') {
      return AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        offset: _isNavBarVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isNavBarVisible ? 1.0 : 0.0,
          child: navBar,
        ),
      );
    }

    return navBar;
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

  IconData _getIconForString(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'home': return Icons.home;
      case 'search': return Icons.search;
      case 'settings': return Icons.settings;
      case 'account_circle': return Icons.account_circle;
      case 'shopping_cart': return Icons.shopping_cart;
      case 'favorite': return Icons.favorite;
      case 'star': return Icons.star;
      case 'notifications': return Icons.notifications;
      case 'info': return Icons.info;
      case 'menu': return Icons.menu;
      case 'mail': return Icons.mail;
      case 'phone': return Icons.phone;
      case 'location_on': return Icons.location_on;
      case 'chat': return Icons.chat;
      case 'camera_alt': return Icons.camera_alt;
      case 'image': return Icons.image;
      case 'article': return Icons.article;
      case 'share': return Icons.share;
      case 'language': return Icons.language;
      case 'dashboard': return Icons.dashboard;
      case 'edit': return Icons.edit;
      case 'delete': return Icons.delete;
      case 'add': return Icons.add;
      case 'check': return Icons.check;
      case 'close': return Icons.close;
      case 'arrow_back': return Icons.arrow_back;
      case 'arrow_forward': return Icons.arrow_forward;
      case 'local_shipping': return Icons.local_shipping;
      case 'payment': return Icons.payment;
      case 'event': return Icons.event;
      case 'history': return Icons.history;
      case 'description': return Icons.description;
      case 'list': return Icons.list;
      case 'category': return Icons.category;
      case 'store': return Icons.store;
      case 'business': return Icons.business;
      case 'flight': return Icons.flight;
      case 'hotel': return Icons.hotel;
      case 'restaurant': return Icons.restaurant;
      case 'directions_car': return Icons.directions_car;
      case 'local_hospital': return Icons.local_hospital;
      case 'school': return Icons.school;
      case 'work': return Icons.work;
      case 'group': return Icons.group;
      case 'person': return Icons.person;
      case 'thumb_up': return Icons.thumb_up;
      case 'thumb_down': return Icons.thumb_down;
      case 'visibility': return Icons.visibility;
      case 'lock': return Icons.lock;
      case 'key': return Icons.key;
      case 'wifi': return Icons.wifi;
      case 'battery_full': return Icons.battery_full;
      case 'build': return Icons.build;
      case 'bug_report': return Icons.bug_report;
      case 'code': return Icons.code;
      case 'help': return Icons.help;
      case 'warning': return Icons.warning;
      case 'error': return Icons.error;
      case 'lightbulb': return Icons.lightbulb;
      case 'attach_file': return Icons.attach_file;
      case 'mic': return Icons.mic;
      case 'videocam': return Icons.videocam;
      case 'play_arrow': return Icons.play_arrow;
      case 'pause': return Icons.pause;
      case 'stop': return Icons.stop;
      case 'volume_up': return Icons.volume_up;
      case 'music_note': return Icons.music_note;
      case 'movie': return Icons.movie;
      case 'tv': return Icons.tv;
      case 'sports_esports': return Icons.sports_esports;
      case 'casino': return Icons.casino;
      case 'fitness_center': return Icons.fitness_center;
      case 'spa': return Icons.spa;
      case 'pets': return Icons.pets;
      case 'explore': return Icons.explore;
      case 'map': return Icons.map;
      case 'place': return Icons.place;
      case 'local_offer': return Icons.local_offer;
      case 'sell': return Icons.sell;
      case 'shopping_bag': return Icons.shopping_bag;
      case 'receipt': return Icons.receipt;
      case 'account_balance': return Icons.account_balance;
      case 'credit_card': return Icons.credit_card;
      case 'monetization_on': return Icons.monetization_on;
      case 'trending_up': return Icons.trending_up;
      case 'analytics': return Icons.analytics;
      case 'bar_chart': return Icons.bar_chart;
      case 'pie_chart': return Icons.pie_chart;
      case 'science': return Icons.science;
      case 'emoji_emotions': return Icons.emoji_emotions;
      case 'sentiment_satisfied': return Icons.sentiment_satisfied;
      case 'water_drop': return Icons.water_drop;
      case 'eco': return Icons.eco;
      case 'wb_sunny': return Icons.wb_sunny;
      case 'nightlight_round': return Icons.nightlight_round;
      case 'cloud': return Icons.cloud;
      case 'ac_unit': return Icons.ac_unit;
      case 'fire_extinguisher': return Icons.fire_extinguisher;
      case 'local_fire_department': return Icons.local_fire_department;
      case 'security': return Icons.security;
      case 'shield': return Icons.shield;
      case 'policy': return Icons.policy;
      case 'gavel': return Icons.gavel;
      case 'apartment': return Icons.apartment;
      case 'house': return Icons.house;
      case 'domain': return Icons.domain;
      case 'public': return Icons.public;
      case 'rocket_launch': return Icons.rocket_launch;
      case 'airport_shuttle': return Icons.airport_shuttle;
      default: return Icons.circle;
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
