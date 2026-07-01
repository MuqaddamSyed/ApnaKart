import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase_client.dart';

/// FCM init + foreground listening + writing to the notifications log.
/// Actual push *sending* should go through a Supabase Edge Function using
/// the FCM server key (never ship the server key in the client). The
/// [sendPushToUser] here only logs the notification row; wire the Edge
/// Function call where indicated.
class NotificationService {
  final _fcm = FirebaseMessaging.instance;

  Future<void> initFCM({required String appRole}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _fcm.requestPermission();
    final token = await _fcm.getToken();
    if (token != null) {
      await _saveToken(uid: uid, token: token, appRole: appRole);
    }
    _fcm.onTokenRefresh.listen(
      (newToken) => _saveToken(uid: uid, token: newToken, appRole: appRole),
    );
  }

  Future<void> _saveToken({
    required String uid,
    required String token,
    required String appRole,
  }) async {
    await supabase.from('device_tokens').upsert({
      'user_id': uid,
      'token': token,
      'platform': 'android',
      'app_role': appRole,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  void listenToForegroundMessages(void Function(RemoteMessage) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }

  /// Logs an in-app notification and asks the Edge Function to deliver FCM.
  Future<void> sendPushToUser(
    String userId,
    String title,
    String body, {
    String type = 'general',
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
      });
      await supabase.functions.invoke('send-push', body: {
        'userId': userId,
        'title': title,
        'body': body,
        'data': {'type': type},
      });
    } catch (_) {
      // Push is best-effort; order flow must continue if FCM is unavailable.
    }
  }

  Future<void> sendPushToRole(
    String appRole,
    String title,
    String body, {
    String type = 'general',
  }) async {
    try {
      await supabase.functions.invoke('send-push', body: {
        'appRole': appRole,
        'title': title,
        'body': body,
        'data': {'type': type},
      });
    } catch (_) {
      // Push is best-effort; order flow must continue if FCM is unavailable.
    }
  }
}
