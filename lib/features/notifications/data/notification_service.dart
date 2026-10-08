import 'dart:async';

import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/notifications/data/notification_settings_repository.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final notificationGatewayProvider = Provider<NotificationGateway>((ref) {
  return FlutterLocalNotificationsGateway(
    plugin: FlutterLocalNotificationsPlugin(),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(gateway: ref.watch(notificationGatewayProvider));
});

final notificationPermissionProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(notificationServiceProvider).isPermissionGranted();
});

final notificationAutomationProvider = Provider<void>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUser?.id;
  final service = ref.watch(notificationServiceProvider);

  if (userId == null) {
    unawaited(service.cancelManagedNotifications());
    return;
  }

  final preferences = ref.watch(notificationPreferencesProvider).asData?.value;
  final syncStatus = ref.watch(syncStatusProvider).asData?.value;

  if (preferences == null || syncStatus == null) {
    return;
  }

  unawaited(
    service.applySchedules(
      preferences: preferences,
      unsyncedCount: syncStatus.unsyncedCount,
    ),
  );
});

abstract class NotificationGateway {
  Future<void> initialize();

  Future<bool> requestPermission();

  Future<bool> isPermissionGranted();

  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  });

  Future<void> cancel(int id);
}

class NotificationService {
  const NotificationService({required this.gateway});

  static const dailyClosingReminderId = 24001;
  static const unsyncedReminderId = 24002;

  final NotificationGateway gateway;

  Future<bool> requestPermission() async {
    await gateway.initialize();
    return gateway.requestPermission();
  }

  Future<bool> isPermissionGranted() async {
    await gateway.initialize();
    return gateway.isPermissionGranted();
  }

  Future<void> applySchedules({
    required NotificationPreferences preferences,
    required int unsyncedCount,
  }) async {
    await gateway.initialize();
    final hasPermission = await gateway.isPermissionGranted();
    if (!hasPermission) {
      await cancelManagedNotifications();
      return;
    }

    if (preferences.dailyClosingReminderEnabled) {
      await gateway.scheduleDaily(
        id: dailyClosingReminderId,
        title: 'Day closing reminder',
        body: 'Wrap up today\'s entries and close the business day report.',
        time: preferences.dailyClosingReminderTime,
      );
    } else {
      await gateway.cancel(dailyClosingReminderId);
    }

    if (preferences.unsyncedReminderEnabled && unsyncedCount > 0) {
      final reminderTime = _offsetTime(
        preferences.dailyClosingReminderTime,
        minutes: 90,
      );
      await gateway.scheduleDaily(
        id: unsyncedReminderId,
        title: 'Unsynced data reminder',
        body: 'You have $unsyncedCount pending local changes waiting to sync.',
        time: reminderTime,
      );
    } else {
      await gateway.cancel(unsyncedReminderId);
    }
  }

  Future<void> cancelManagedNotifications() async {
    await gateway.cancel(dailyClosingReminderId);
    await gateway.cancel(unsyncedReminderId);
  }

  static TimeOfDay _offsetTime(TimeOfDay base, {required int minutes}) {
    final totalMinutes = ((base.hour * 60) + base.minute + minutes) % (24 * 60);
    final normalized = totalMinutes < 0
        ? totalMinutes + (24 * 60)
        : totalMinutes;
    return TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60);
  }
}

class FlutterLocalNotificationsGateway implements NotificationGateway {
  FlutterLocalNotificationsGateway({required this.plugin});

  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;

  static const _dailyClosingChannel = 'daily_closing_reminders';
  static const _unsyncedChannel = 'unsynced_data_reminders';

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    await plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    } catch (_) {
      // Keep timezone defaults if Asia/Karachi is not available.
    }

    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macos = plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final granted = await macos?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  @override
  Future<bool> isPermissionGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    }

    // On non-Android targets, treat permissions as available unless the
    // request call reports otherwise.
    return true;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        id == NotificationService.dailyClosingReminderId
            ? _dailyClosingChannel
            : _unsyncedChannel,
        id == NotificationService.dailyClosingReminderId
            ? 'Daily closing reminders'
            : 'Unsynced data reminders',
        channelDescription: id == NotificationService.dailyClosingReminderId
            ? 'Reminds you to close the business day.'
            : 'Reminds you when unsynced data is pending.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstance(time),
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel(int id) => plugin.cancel(id);

  tz.TZDateTime _nextInstance(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
