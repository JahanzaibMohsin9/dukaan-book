import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/features/notifications/data/notification_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late NotificationSettingsRepository repository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = NotificationSettingsRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('defaults to expected reminder preferences', () async {
    final preferences = await repository.watchPreferences().first;

    expect(preferences.dailyClosingReminderEnabled, isFalse);
    expect(
      preferences.dailyClosingReminderTime,
      const TimeOfDay(hour: 21, minute: 0),
    );
    expect(preferences.unsyncedReminderEnabled, isTrue);
  });

  test('persists reminder settings in app settings table', () async {
    await repository.setDailyClosingReminderEnabled(true);
    await repository.setDailyClosingReminderTime(
      const TimeOfDay(hour: 20, minute: 45),
    );
    await repository.setUnsyncedReminderEnabled(false);

    final preferences = await repository.watchPreferences().first;

    expect(preferences.dailyClosingReminderEnabled, isTrue);
    expect(
      preferences.dailyClosingReminderTime,
      const TimeOfDay(hour: 20, minute: 45),
    );
    expect(preferences.unsyncedReminderEnabled, isFalse);
  });
}
