import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'user_service.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final UserService _userService = UserService();
  StreamSubscription<String>? _tokenSubscription;

  Future<bool> enableForUser(String uid) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }

    final token = await _messaging.getToken();
    if (token != null) {
      await _userService.addFcmToken(uid, token);
    }

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
}
