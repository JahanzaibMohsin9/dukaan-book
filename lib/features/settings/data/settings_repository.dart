import 'dart:io';

import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final settingsOutboxProvider = Provider<SettingsOutbox>((ref) {
  final writer = ref.watch(syncServiceProvider).outboxWriter;
  return SyncSettingsOutbox(writer: writer);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    database: ref.watch(appDatabaseProvider),
    outbox: ref.watch(settingsOutboxProvider),
  );
});

final activeShopProfileProvider =
    StreamProvider.autoDispose<ShopSettingsProfile?>((ref) {
      final userId = ref.watch(authRepositoryProvider).currentUser?.id;
      if (userId == null) {
        return Stream.value(null);
      }
      return ref
          .watch(settingsRepositoryProvider)
          .watchActiveShopProfile(userId: userId);
    });

class ShopSettingsProfile {
  const ShopSettingsProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.city,
    required this.phone,
    required this.timezone,
    required this.dayCloseTime,
  });

  final String id;
  final String userId;
  final String name;
  final String? city;
  final String? phone;
  final String timezone;
  final String dayCloseTime;
}

class LocalBackupResult {
  const LocalBackupResult({
    required this.filePath,
    required this.fileSizeBytes,
  });

  final String filePath;
  final int fileSizeBytes;
}

abstract class SettingsOutbox {
  Future<void> queueUpsert({
    required String table,
    required String recordId,
    required Map<String, Object?> payload,
  });
}

class SyncSettingsOutbox implements SettingsOutbox {
  const SyncSettingsOutbox({required this.writer});

  final OutboxWriter writer;

  @override
  Future<void> queueUpsert({
    required String table,
    required String recordId,
    required Map<String, Object?> payload,
  }) {
    return writer.upsert(table: table, recordId: recordId, payload: payload);
  }
}

class SettingsRepository {
  SettingsRepository({
    required this.database,
    required this.outbox,
    Future<Directory> Function()? appDocumentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _appDocumentsDirectory =
           appDocumentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final AppDatabase database;
  final SettingsOutbox outbox;
  final Future<Directory> Function() _appDocumentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  Stream<ShopSettingsProfile?> watchActiveShopProfile({
    required String userId,
  }) {
    return database
        .customSelect(
          '''
          SELECT *
          FROM shops
          WHERE id = (${_activeShopSql(userId)})
          LIMIT 1
          ''',
          readsFrom: {database.shops, database.shopMembers},
        )
        .watchSingleOrNull()
        .map((row) {
          final shop = row == null ? null : database.shops.map(row.data);
          if (shop == null) {
            return null;
          }
          return ShopSettingsProfile(
            id: shop.id,
            userId: shop.userId,
            name: shop.name,
            city: shop.city,
            phone: shop.phone,
            timezone: shop.timezone,
            dayCloseTime: shop.dayCloseTime,
          );
        });
  }

  Future<void> updateShopProfile({
    required ShopSettingsProfile profile,
    required String shopName,
    String? city,
    String? phone,
  }) async {
    final trimmedName = shopName.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('Shop name is required.');
    }

    final now = DateTime.now().toUtc();
    final trimmedCity = _nullableTrim(city);
    final trimmedPhone = _nullableTrim(phone);

    await (database.update(
      database.shops,
    )..where((row) => row.id.equals(profile.id))).write(
      ShopsCompanion(
        name: Value(trimmedName),
        city: Value(trimmedCity),
        phone: Value(trimmedPhone),
        updatedAt: Value(now),
      ),
    );

    await outbox.queueUpsert(
      table: 'shops',
      recordId: profile.id,
      payload: {
        'id': profile.id,
        'user_id': profile.userId,
        'name': trimmedName,
        'city': trimmedCity,
        'phone': trimmedPhone,
        'timezone': profile.timezone,
        'day_close_time': profile.dayCloseTime,
      },
    );
  }

  Future<LocalBackupResult> createLocalDatabaseBackup() async {
    final sourceDir = await _appDocumentsDirectory();
    final sourceFile = File(p.join(sourceDir.path, appDatabaseFileName));
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Local database file was not found.');
    }

    final destinationDir = await _temporaryDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.-]'),
      '',
    );
    final destinationPath = p.join(
      destinationDir.path,
      'dukaan_book_backup_$stamp.sqlite',
    );

    final copied = await sourceFile.copy(destinationPath);
    final size = await copied.length();
    return LocalBackupResult(filePath: copied.path, fileSizeBytes: size);
  }

  Future<int> pendingUnsyncedCount() async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_outbox WHERE synced_at IS NULL',
          readsFrom: {database.syncOutbox},
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> clearLocalCache() async {
    await database.transaction(() async {
      await database.delete(database.syncState).go();
      await (database.delete(
        database.syncOutbox,
      )..where((row) => row.syncedAt.isNotNull())).go();
    });
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

String _activeShopSql(String userId) {
  final escaped = userId.replaceAll("'", "''");
  return '''
SELECT id FROM shops
WHERE deleted_at IS NULL
  AND (
    user_id = '$escaped'
    OR EXISTS (
      SELECT 1
      FROM shop_members AS sm
      WHERE sm.shop_id = shops.id
        AND sm.user_id = '$escaped'
        AND sm.deleted_at IS NULL
    )
  )
ORDER BY created_at DESC
LIMIT 1
''';
}
