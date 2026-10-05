import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_notification_service.dart';

class VendorFcmService {
  static final _messaging = FirebaseMessaging.instance;

  /// Initialize FCM for a vendor. Skips dodo_team users (user_type != 'vendor').
  static Future<void> initialize(String vendorId, String phone) async {
    await _messaging.requestPermission(
      alert: true,
      sound: true,
      badge: true,
    );

    final token = await _messaging.getToken();
    if (token == null) return;

    await _registerToken(vendorId, phone, token);

    _messaging.onTokenRefresh.listen((newToken) {
      _registerToken(vendorId, phone, newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      LocalNotificationService.show(message);
    });
  }

  static Future<void> clearToken(String vendorId, String phone) async {
    final token = await _messaging.getToken();
    if (token != null) {
      try {
        await Supabase.instance.client.rpc('deactivate_device_token', params: {
          'p_user_type': 'vendor',
          'p_user_id': vendorId,
          'p_token': token,
          'p_phone': phone,
        });
      } catch (_) {}
    }
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  static Future<void> _registerToken(
    String vendorId,
    String phone,
    String token,
  ) async {
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_user_type': 'vendor',
        'p_user_id': vendorId,
        'p_platform': _platform(),
        'p_token': token,
        'p_phone': phone,
      });
    } catch (_) {
      debugPrint('[FCM][Vendor] Token registration failed');
    }
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }
}
