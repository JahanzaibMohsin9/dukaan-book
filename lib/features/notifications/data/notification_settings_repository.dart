import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      return NotificationSettingsRepository(
        database: ref.watch(appDatabaseProvider),
      );
    });

final notificationPreferencesProvider =
    StreamProvider.autoDispose<NotificationPreferences>((ref) {
      return ref
          .watch(notificationSettingsRepositoryProvider)
          .watchPreferences();
    });

class NotificationPreferences {
  const NotificationPreferences({
    required this.dailyClosingReminderEnabled,
    required this.dailyClosingReminderTime,
    required this.unsyncedReminderEnabled,
  });

  static const defaultDailyClosingReminderEnabled = false;
  static const defaultUnsyncedReminderEnabled = true;
  static const defaultDailyClosingReminderTime = TimeOfDay(hour: 21, minute: 0);

  final bool dailyClosingReminderEnabled;
  final TimeOfDay dailyClosingReminderTime;
  final bool unsyncedReminderEnabled;

  NotificationPreferences copyWith({
    bool? dailyClosingReminderEnabled,
    TimeOfDay? dailyClosingReminderTime,
    bool? unsyncedReminderEnabled,
  }) {
    return NotificationPreferences(
      dailyClosingReminderEnabled:
          dailyClosingReminderEnabled ?? this.dailyClosingReminderEnabled,
      dailyClosingReminderTime:
          dailyClosingReminderTime ?? this.dailyClosingReminderTime,
      unsyncedReminderEnabled:
          unsyncedReminderEnabled ?? this.unsyncedReminderEnabled,
    );
  }
}

class NotificationSettingsRepository {
  const NotificationSettingsRepository({required this.database});

  static const dailyClosingEnabledKey = 'notifications.daily_closing.enabled';
  static const dailyClosingTimeKey = 'notifications.daily_closing.time';
  static const unsyncedReminderEnabledKey = 'notifications.unsynced.enabled';

  final AppDatabase database;

  Stream<NotificationPreferences> watchPreferences() {
    return (database.select(database.appSettings)..where(
          (row) => row.key.isIn([
            dailyClosingEnabledKey,
            dailyClosingTimeKey,
            unsyncedReminderEnabledKey,
          ]),
        ))
        .watch()
        .map((rows) {
          final values = <String, String>{
            for (final row in rows) row.key: row.value,
          };

          return NotificationPreferences(
            dailyClosingReminderEnabled: _asBool(
              values[dailyClosingEnabledKey],
              NotificationPreferences.defaultDailyClosingReminderEnabled,
            ),
            dailyClosingReminderTime: _asTimeOfDay(
              values[dailyClosingTimeKey],
              NotificationPreferences.defaultDailyClosingReminderTime,
            ),
            unsyncedReminderEnabled: _asBool(
              values[unsyncedReminderEnabledKey],
              NotificationPreferences.defaultUnsyncedReminderEnabled,
            ),
          );
        });
  }

  Future<void> setDailyClosingReminderEnabled(bool enabled) {
    return _setValue(dailyClosingEnabledKey, enabled ? 'true' : 'false');
  }

  Future<void> setDailyClosingReminderTime(TimeOfDay time) {
    return _setValue(dailyClosingTimeKey, _formatTime(time));
  }

  Future<void> setUnsyncedReminderEnabled(bool enabled) {
    return _setValue(unsyncedReminderEnabledKey, enabled ? 'true' : 'false');
  }

  Future<void> _setValue(String key, String value) {
    final now = DateTime.now().toUtc();
    return database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: Value(key),
            value: Value(value),
            updatedAt: Value(now),
          ),
        );
  }

  static bool _asBool(String? value, bool fallback) {
    if (value == null) {
      return fallback;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return fallback;
  }

  static TimeOfDay _asTimeOfDay(String? value, TimeOfDay fallback) {
    if (value == null) {
      return fallback;
    }

    final parts = value.split(':');
    if (parts.length != 2) {
      return fallback;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return fallback;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return fallback;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
