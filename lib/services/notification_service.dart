import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'user_service.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final UserService _userService = UserService();
  StreamSubscription<String>? _tokenSubscription;

  bool _isAuthorized(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<String?> _getTokenWithRetry() async {
    String? token;
    for (int attempt = 0; attempt < 3; attempt++) {
      token = await _messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        return token;
      }
      await Future<void>.delayed(Duration(milliseconds: 450 + (attempt * 300)));
    }
    return null;
  }

  Future<bool> enableForUser(String uid) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final isAuthorized = _isAuthorized(settings.authorizationStatus);
    if (!isAuthorized) {
      return false;
    }

    await _userService.setNotificationsEnabled(uid, true);

    String? token = await _getTokenWithRetry();
    if (token == null || token.trim().isEmpty) {
      try {
        await _messaging.deleteToken();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
      token = await _getTokenWithRetry();
    }
    if (token == null || token.trim().isEmpty) {
      return false;
    }
    await _userService.addFcmToken(uid, token);

    _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen((newToken) {
      _userService.addFcmToken(uid, newToken);
    });

    return true;
  }

  Future<void> disableForUser(String uid) async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _userService.removeFcmToken(uid, token);
    }
    await _messaging.deleteToken();
    await _tokenSubscription?.cancel();
  }

  Future<NotificationDiagnostic> getDiagnostic() async {
    final settings = await _messaging.getNotificationSettings();
    final token = await _messaging.getToken();
    return NotificationDiagnostic(
      authorizationStatus: settings.authorizationStatus,
      currentToken: token,
    );
  }
}

class NotificationDiagnostic {
  final AuthorizationStatus authorizationStatus;
  final String? currentToken;

  const NotificationDiagnostic({
    required this.authorizationStatus,
    required this.currentToken,
  });
}
