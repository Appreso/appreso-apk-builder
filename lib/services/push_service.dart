import 'dart:async';

class PushService {
  static final PushService _instance = PushService._internal();

  factory PushService() {
    return _instance;
  }

  PushService._internal();

  final _launchUrlController = StreamController<String>.broadcast();
  String? _pendingLaunchUrl;

  Stream<String> get onLaunchUrl => _launchUrlController.stream;

  void handleNotificationClick(String? url) {
    if (url != null && url.isNotEmpty) {
      _pendingLaunchUrl = url;
      _launchUrlController.add(url);
    }
  }

  String? consumePendingUrl() {
    final url = _pendingLaunchUrl;
    _pendingLaunchUrl = null;
    return url;
  }
}

final pushService = PushService();
