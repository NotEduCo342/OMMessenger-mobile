import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'om_messages';
  static const String _channelName = 'Messages';
  static const String _channelDescription = 'Message notifications';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
    );
    await _plugin.initialize(settings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  int _conversationSummaryId(String conversationId) => conversationId.hashCode ^ 0x7fffffff;

  Future<void> showMessage({
    required String conversationId,
    required int messageId,
    required String title,
    required String body,
  }) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        groupKey: conversationId,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
    );

    await _plugin.show(messageId, title, body, details, payload: conversationId);
  }

  Future<void> showConversationSummary({
    required String conversationId,
    required String title,
    required String body,
    required int messageCount,
  }) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        groupKey: conversationId,
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          [body],
          contentTitle: title,
          summaryText: '$messageCount new messages',
        ),
      ),
    );

    await _plugin.show(
      _conversationSummaryId(conversationId),
      title,
      body,
      details,
      payload: conversationId,
    );
  }

  Future<void> cancelConversation(String conversationId) async {
    await init();
    await _plugin.cancel(_conversationSummaryId(conversationId));
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
