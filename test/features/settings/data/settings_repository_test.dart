import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late _FakeSettingsOutbox outbox;
  late SettingsRepository repository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    outbox = _FakeSettingsOutbox();
    repository = SettingsRepository(database: database, outbox: outbox);
  });

  tearDown(() async {
    await database.close();
  });

  test('updates shop profile and queues sync outbox payload', () async {
    final now = DateTime.utc(2026, 4, 13, 12);

    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'user-1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(
            id: 'shop-1',
            userId: 'user-1',
            name: 'Old Shop',
            city: const Value('Lahore'),
            phone: const Value('0300-0000000'),
            timezone: const Value('Asia/Karachi'),
            dayCloseTime: const Value('21:00'),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await repository.updateShopProfile(
      profile: const ShopSettingsProfile(
        id: 'shop-1',
        userId: 'user-1',
        name: 'Old Shop',
        city: 'Lahore',
        phone: '0300-0000000',
        timezone: 'Asia/Karachi',
        dayCloseTime: '21:00',
      ),
      shopName: 'New Shop',
      city: 'Karachi',
      phone: '0311-1111111',
    );

    final updated = await (database.select(
      database.shops,
    )..where((row) => row.id.equals('shop-1'))).getSingle();

    expect(updated.name, 'New Shop');
    expect(updated.city, 'Karachi');
    expect(updated.phone, '0311-1111111');

    expect(outbox.calls, hasLength(1));
    final call = outbox.calls.single;
    expect(call.table, 'shops');
    expect(call.recordId, 'shop-1');
    expect(call.payload['name'], 'New Shop');
    expect(call.payload['city'], 'Karachi');
  });

  test(
    'clearLocalCache removes sync state and only synced outbox rows',
    () async {
      final now = DateTime.utc(2026, 4, 13, 10);

      await database
          .into(database.syncState)
          .insert(
            SyncStateCompanion.insert(
              key: 'last_pull_at',
              value: now.toIso8601String(),
              updatedAt: now,
            ),
          );

      await database
          .into(database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: 'synced-item',
              targetTableName: 'shops',
              recordId: 'shop-1',
              operation: 'upsert',
              payloadJson: jsonEncode({'id': 'shop-1'}),
              createdAt: now,
              syncedAt: Value(now),
            ),
          );

      await database
          .into(database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: 'pending-item',
              targetTableName: 'shops',
              recordId: 'shop-2',
              operation: 'upsert',
              payloadJson: jsonEncode({'id': 'shop-2'}),
              createdAt: now,
            ),
          );

      await repository.clearLocalCache();

      final states = await database.select(database.syncState).get();
      final outboxRows = await database.select(database.syncOutbox).get();

      expect(states, isEmpty);
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.id, 'pending-item');
    },
  );

  test('creates local sqlite backup file in temp directory', () async {
    final sourceDir = await Directory.systemTemp.createTemp('dukaan_source_');
    final targetDir = await Directory.systemTemp.createTemp('dukaan_target_');

    addTearDown(() async {
      if (await sourceDir.exists()) {
        await sourceDir.delete(recursive: true);
      }
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    });

    final sourceFile = File(p.join(sourceDir.path, appDatabaseFileName));
    await sourceFile.writeAsBytes(utf8.encode('sqlite-backup-test'));

    final localRepository = SettingsRepository(
      database: database,
      outbox: outbox,
      appDocumentsDirectory: () async => sourceDir,
      temporaryDirectory: () async => targetDir,
    );

    final result = await localRepository.createLocalDatabaseBackup();

    final copiedFile = File(result.filePath);
    expect(await copiedFile.exists(), isTrue);
    expect(result.fileSizeBytes, greaterThan(0));
    expect(await copiedFile.readAsString(), 'sqlite-backup-test');
  });
}

class _FakeSettingsOutbox implements SettingsOutbox {
  final List<_OutboxCall> calls = <_OutboxCall>[];

  @override
  Future<void> queueUpsert({
    required String table,
    required String recordId,
    required Map<String, Object?> payload,
  }) async {
    calls.add(_OutboxCall(table: table, recordId: recordId, payload: payload));
  }
}

class _OutboxCall {
  const _OutboxCall({
    required this.table,
    required this.recordId,
    required this.payload,
  });

  final String table;
  final String recordId;
  final Map<String, Object?> payload;
}
