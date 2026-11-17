// What the workout logger asks of the phone: a buzz on a tick and at the end of a rest, the screen
// kept awake while the logger is open, and a local notification when a rest ends with the app in
// the background. Behind one seam so widget tests run without the platform plugins.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

abstract class WorkoutDevice {
  /// The device the app uses; tests put a fake here.
  static WorkoutDevice instance = PluginWorkoutDevice();

  /// Sets the notification plugin up (main.dart, once at launch).
  Future<void> init();

  /// Asks for notification permission (the first workout: Android 13+, iOS).
  Future<void> requestPermissions();

  /// A local notification at [at] saying the rest is over; replaces one already booked.
  Future<void> scheduleRestEnd(DateTime at);

  /// Takes the booked rest notification down (back in the app, Skip, a new rest).
  Future<void> cancelRestEnd();

  Future<void> keepAwake(bool on);

  /// The light tap that confirms a ticked set.
  void tickHaptic();

  /// The rest is over: a short double buzz.
  void restOverBuzz();
}

/// The real thing: flutter_local_notifications, wakelock_plus and the platform haptics. Every call
/// swallows its errors — a notification that cannot be booked must never break logging a set.
class PluginWorkoutDevice implements WorkoutDevice {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  static const _restId = 4201;
  static const _channel = AndroidNotificationChannel(
    'rest',
    'Rest timer',
    description: 'Tells you when a rest between sets is over.',
    importance: Importance.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked on the first workout, not at launch.
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      await _android?.createNotificationChannel(_channel);
      _ready = true;
    } catch (_) {}
  }

  @override
  Future<void> requestPermissions() async {
    if (_asked || kIsWeb) return;
    _asked = true;
    try {
      await init();
      await _android?.requestNotificationsPermission();
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        sound: true,
      );
    } catch (_) {}
  }

  @override
  Future<void> scheduleRestEnd(DateTime at) async {
    if (!_ready) return;
    try {
      // An absolute instant: UTC needs no time-zone database.
      final when = tz.TZDateTime.from(at.toUtc(), tz.UTC);
      final exact = await _android?.canScheduleExactNotifications() ?? true;
      await _plugin.zonedSchedule(
        id: _restId,
        title: 'Rest’s over',
        body: 'Next set — you’ve got this.',
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            timeoutAfter: 10 * 60 * 1000,
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
        ),
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  @override
  Future<void> cancelRestEnd() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _restId);
    } catch (_) {}
  }

  @override
  Future<void> keepAwake(bool on) async {
    try {
      await (on ? WakelockPlus.enable() : WakelockPlus.disable());
    } catch (_) {}
  }

  @override
  void tickHaptic() {
    unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  @override
  void restOverBuzz() {
    unawaited(() async {
      try {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }());
  }
}

/// A device that does nothing and remembers what it was asked (tests).
class FakeWorkoutDevice implements WorkoutDevice {
  final List<String> calls = [];
  DateTime? booked;
  bool awake = false;

  @override
  Future<void> init() async => calls.add('init');

  @override
  Future<void> requestPermissions() async => calls.add('permissions');

  @override
  Future<void> scheduleRestEnd(DateTime at) async {
    booked = at;
    calls.add('schedule');
  }

  @override
  Future<void> cancelRestEnd() async {
    booked = null;
    calls.add('cancel');
  }

  @override
  Future<void> keepAwake(bool on) async {
    awake = on;
    calls.add(on ? 'awake' : 'asleep');
  }

  @override
  void tickHaptic() => calls.add('tick');

  @override
  void restOverBuzz() => calls.add('buzz');
}
