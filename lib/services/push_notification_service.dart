import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles a push that arrives while the app is backgrounded or killed.
///
/// Runs in its own isolate with no access to app state, so it only initialises
/// Firebase. The tray notification itself is drawn by FCM from the `notification`
/// block the Edge Function sends, which is what makes it survive the app being
/// swiped away.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  developer.log('Background push received: ${message.messageId}');
}

/// Firebase Cloud Messaging wiring for rider notifications.
///
/// Android configuration is read from `android/app/google-services.json` by the
/// google-services Gradle plugin, so no generated `firebase_options.dart` is
/// needed here.
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() {
    return _instance;
  }

  PushNotificationService._internal();

  /// Must match `default_notification_channel_id` in AndroidManifest.xml, or
  /// backgrounded pushes land on a channel the rider never allowed.
  static const String channelId = 'sc_courier_deliveries';
  static const String channelName = 'Delivery updates';
  static const String channelDescription =
      'New assignments and changes to your deliveries';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isInitialized = false;
  Map<String, dynamic>? _launchPayload;

  /// Emits the `data` block of a notification the rider tapped.
  Stream<Map<String, dynamic>> get onNotificationTap => _tapController.stream;

  /// Set when a tapped notification cold-started the app. Read once, by the
  /// first screen ready to navigate.
  Map<String, dynamic>? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  /// True once the rider has granted notification permission.
  final ValueNotifier<bool> isAuthorized = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _createAndroidChannel();
      await _initializeLocalNotifications();
      await _requestPermission();

      // Foreground messages are not drawn by the system, so mirror them onto a
      // local notification using the same channel.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // Tapped while the app was backgrounded but alive.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _emitTap(message.data);
      });

      // Tapped while the app was not running at all.
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        _launchPayload = Map<String, dynamic>.from(initialMessage.data);
      }

      _isInitialized = true;
      developer.log('Push notification service initialized');
    } catch (e) {
      // A missing google-services.json or an unavailable Play Services must not
      // stop the app from starting.
      developer.log('Error initializing push notifications: $e');
    }
  }

  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _initializeLocalNotifications() async {
    const settings = InitializationSettings(
      // Drawable name only: Android masks it to a white silhouette.
      android: AndroidInitializationSettings('ic_notification'),
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _emitTap(_decodePayload(payload));
      },
    );
  }

  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    isAuthorized.value =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    developer.log('Notification permission: ${settings.authorizationStatus}');
  }

  /// Re-asks for permission. Android only shows the system dialog once, so a
  /// rider who declined has to enable it in Settings; [isAuthorized] reflects
  /// the outcome either way.
  Future<bool> ensurePermission() async {
    await _requestPermission();
    return isAuthorized.value;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null && body == null) return;

    await _localNotifications.show(
      // Millisecond-derived id: unique per notification without a counter that
      // resets when the app restarts.
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
      ),
      payload: _encodePayload(message.data),
    );
  }

  void _emitTap(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _tapController.add(data);
  }

  /// FCM data values are always strings, so the payload round-trips as JSON.
  String _encodePayload(Map<String, dynamic> data) => jsonEncode(data);

  Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      developer.log('Could not decode notification payload: $e');
    }
    return const {};
  }

  /// The device's FCM registration token, or null if messaging is unavailable.
  Future<String?> getFCMToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      developer.log('Error getting FCM token: $e');
      return null;
    }
  }

  /// Fires whenever FCM rotates the token, which can happen at any time.
  StreamSubscription<String> onTokenRefresh(
    void Function(String token) onToken,
  ) {
    return FirebaseMessaging.instance.onTokenRefresh.listen(onToken);
  }

  /// Drops the device's token so a signed-out phone stops receiving pushes for
  /// the rider who was using it.
  Future<void> deleteToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      developer.log('Error deleting FCM token: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      developer.log('Subscribed to topic: $topic');
    } catch (e) {
      developer.log('Error subscribing to topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      developer.log('Unsubscribed from topic: $topic');
    } catch (e) {
      developer.log('Error unsubscribing from topic: $e');
    }
  }
}
