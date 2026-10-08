import 'package:dukaan_book/features/notifications/data/notification_service.dart';
import 'package:dukaan_book/features/notifications/data/notification_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeNotificationGateway gateway;
  late NotificationService service;

  setUp(() {
    gateway = _FakeNotificationGateway();
    service = NotificationService(gateway: gateway);
  });

  test(
    'Android 13 denied permission blocks schedules and cancels reminders',
    () async {
      gateway.permissionGranted = false;
      gateway.scheduled[NotificationService.dailyClosingReminderId] =
          const _Scheduled('old', 'old', TimeOfDay(hour: 21, minute: 0));
      gateway.scheduled[NotificationService.unsyncedReminderId] =
          const _Scheduled('old', 'old', TimeOfDay(hour: 22, minute: 30));

      await service.applySchedules(
        preferences: const NotificationPreferences(
          dailyClosingReminderEnabled: true,
          dailyClosingReminderTime: TimeOfDay(hour: 21, minute: 0),
          unsyncedReminderEnabled: true,
        ),
        unsyncedCount: 3,
      );

      expect(gateway.scheduled, isEmpty);
      expect(
        gateway.cancelledIds,
        contains(NotificationService.dailyClosingReminderId),
      );
      expect(
        gateway.cancelledIds,
        contains(NotificationService.unsyncedReminderId),
      );
    },
  );

  test('schedules both daily and unsynced reminders when allowed', () async {
    gateway.permissionGranted = true;

    await service.applySchedules(
      preferences: const NotificationPreferences(
        dailyClosingReminderEnabled: true,
        dailyClosingReminderTime: TimeOfDay(hour: 21, minute: 0),
        unsyncedReminderEnabled: true,
      ),
      unsyncedCount: 5,
    );

    final daily = gateway.scheduled[NotificationService.dailyClosingReminderId];
    final unsynced = gateway.scheduled[NotificationService.unsyncedReminderId];

    expect(daily, isNotNull);
    expect(daily!.title, 'Day closing reminder');
    expect(daily.time, const TimeOfDay(hour: 21, minute: 0));

    expect(unsynced, isNotNull);
    expect(unsynced!.title, 'Unsynced data reminder');
    expect(unsynced.time, const TimeOfDay(hour: 22, minute: 30));
  });

  test('requestPermission forwards to gateway behavior', () async {
    gateway.permissionGranted = false;
    expect(await service.requestPermission(), isFalse);

    gateway.permissionGranted = true;
    expect(await service.requestPermission(), isTrue);
    expect(gateway.requestPermissionCalls, 2);
  });
}

class _FakeNotificationGateway implements NotificationGateway {
  bool initialized = false;
  bool permissionGranted = true;
  int requestPermissionCalls = 0;
  final List<int> cancelledIds = <int>[];
  final Map<int, _Scheduled> scheduled = <int, _Scheduled>{};

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    return permissionGranted;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    scheduled[id] = _Scheduled(title, body, time);
  }
}

class _Scheduled {
  const _Scheduled(this.title, this.body, this.time);

  final String title;
  final String body;
  final TimeOfDay time;
}
