import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminFcmService {
  static final _messaging = FirebaseMessaging.instance;

  // Replace this with the VAPID key from Firebase Console → Project Settings → Cloud Messaging → Web Push certificates.
  static const _vapidKey = 'BAkda1qS0VYMnk8IsLiBBrhQ4Ilhn13hUyvRSXZkobKz6UWfzIU-DzW5s-02EgFQwX1q-4M3uDW8vvJjMuesFCY';

  static final _foregroundController =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of foreground messages; DodoAdminApp listens to show in-app banners.
  static Stream<RemoteMessage> get foregroundStream =>
      _foregroundController.stream;

  static Future<void> initialize(String adminUserId) async {
    debugPrint('[FCM][Admin] initialize started — adminId available: ${adminUserId.isNotEmpty}');

    final settings = await _messaging.requestPermission(alert: true, sound: true, badge: true);
    debugPrint('[FCM][Admin] permission result: ${settings.authorizationStatus}');

    String? token;
    try {
      token = await _messaging.getToken(vapidKey: _vapidKey);
    } catch (e) {
      debugPrint('[FCM][Admin] getToken error: ${e.runtimeType}');
    }
    debugPrint('[FCM][Admin] getToken success: ${token != null}, length: ${token?.length ?? 0}');
    if (token == null) return;

    await _registerToken(adminUserId, token);

    _messaging.onTokenRefresh.listen((newToken) {
      _registerToken(adminUserId, newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      _foregroundController.add(message);
    });
  }

  static Future<void> clearToken(String adminUserId) async {
    final token = await _messaging.getToken(vapidKey: _vapidKey);
    if (token != null) {
      try {
        await Supabase.instance.client.rpc('deactivate_device_token', params: {
          'p_user_type': 'admin',
          'p_user_id': adminUserId,
          'p_token': token,
        });
      } catch (_) {}
    }
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  static Future<void> _registerToken(String adminUserId, String token) async {
    debugPrint('[FCM][Admin] RPC register_device_token called — user_type=admin, platform=web');
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_user_type': 'admin',
        'p_user_id': adminUserId,
        'p_platform': 'web',
        'p_token': token,
      });
      debugPrint('[FCM][Admin] RPC success — token registered');
    } catch (e) {
      debugPrint('[FCM][Admin] RPC failed: ${e.runtimeType} — ${e.toString().split('\n').first}');
    }
  }
}
