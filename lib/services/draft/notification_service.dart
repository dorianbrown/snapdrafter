import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  AppLifecycleState lifecycleState = AppLifecycleState.resumed;

  bool get _inBackground =>
      lifecycleState == AppLifecycleState.paused ||
      lifecycleState == AppLifecycleState.detached;

  static const _channelId = 'draft_events';
  static const _channelName = 'Draft Events';
  static const _channelDescription =
      'Notifications for draft session events';

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _createChannel();
  }

  Future<void> _createChannel() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );
  }

  AndroidNotificationDetails _androidDetails() {
    return const AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.event,
      enableVibration: true,
      playSound: true,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
    );
  }

  DarwinNotificationDetails _darwinDetails() {
    return const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
  }

  NotificationDetails _details() {
    return NotificationDetails(
      android: _androidDetails(),
      iOS: _darwinDetails(),
      macOS: _darwinDetails(),
    );
  }

  Future<void> _show(int id, String title, String body) async {
    await _plugin.show(
      id,
      title,
      body,
      _details(),
    );
  }

  // --------------------------------------------------------------------------
  // Match result submitted
  // --------------------------------------------------------------------------

  void notifyMatchResultSubmitted({
    required String reporterName,
    required String opponentName,
    required int reporterWins,
    required int opponentWins,
    required int roundNumber,
  }) {
    final title = 'Match Result Submitted';
    final body =
        '$reporterName reported $reporterWins-$opponentWins vs $opponentName (Round $roundNumber)';

    if (!_inBackground) return;

    _show(200 + roundNumber, title, body);
  }

  // --------------------------------------------------------------------------
  // Round time elapsed
  // --------------------------------------------------------------------------

  void notifyRoundTimeElapsed({required int roundNumber}) {
    final title = 'Time\'s Up!';
    final body = 'Round $roundNumber time has elapsed. '
        'Please submit your match results.';

    if (!_inBackground) return;

    _show(300 + roundNumber, title, body);
  }

  // --------------------------------------------------------------------------
  // New round started
  // --------------------------------------------------------------------------

  void notifyNewRound({
    required int roundNumber,
    required int totalRounds,
    String? opponentName,
  }) {
    final title = 'Round $roundNumber Started';
    final String body;
    if (opponentName != null) {
      body = 'Round $roundNumber of $totalRounds. '
          'You are paired vs $opponentName.';
    } else {
      body = 'Round $roundNumber of $totalRounds. '
          'You have a bye this round.';
    }

    if (!_inBackground) return;

    _show(400 + roundNumber, title, body);
  }
}
