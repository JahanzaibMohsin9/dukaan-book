import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late FakeRemoteStore remote;
  late SyncService service;
  late IdGenerator idGenerator;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    remote = FakeRemoteStore();
    idGenerator = IdGenerator();
    service = SyncService(
      database: database,
      idGenerator: idGenerator,
      remote: remote,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('pushes pending outbox items and marks them synced', () async {
    final now = DateTime.utc(2026, 4, 13);
    await service.outboxWriter.upsert(
      table: 'accounts',
      recordId: 'account-1',
      payload: {'id': 'account-1', 'user_id': 'user-1', 'name': 'Cash'},
      now: now,
    );

    await service.pushOutbox();

    final outbox = await database.select(database.syncOutbox).getSingle();
    expect(remote.upserts['accounts']?.single['id'], 'account-1');
    expect(outbox.syncedAt, isNotNull);
    expect(outbox.lastError, isNull);
  });

  test('records retry metadata when a push fails', () async {
    remote.failUpserts = true;
    await service.outboxWriter.upsert(
      table: 'accounts',
      recordId: 'account-1',
      payload: {'id': 'account-1'},
    );

    await expectLater(service.pushOutbox(), throwsA(isA<SyncPushException>()));

    final outbox = await database.select(database.syncOutbox).getSingle();
    expect(outbox.syncedAt, isNull);
    expect(outbox.attemptCount, 1);
    expect(outbox.lastAttemptAt, isNotNull);
    expect(outbox.lastError, contains('remote failed'));
  });

  test('syncNow keeps failure visible when push fails', () async {
    remote.failUpserts = true;
    await service.outboxWriter.upsert(
      table: 'accounts',
      recordId: 'account-1',
      payload: {'id': 'account-1'},
    );

    await service.syncNow(userId: 'user-1');

    final status = await service.watchStatus().first;
    final lastSuccessfulSync =
        await (database.select(database.syncState)
              ..where((row) => row.key.equals('last_successful_sync_at')))
            .getSingleOrNull();

    expect(status.unsyncedCount, 1);
    expect(status.lastError, contains('failed to upload'));
    expect(lastSuccessfulSync, isNull);
  });

  test('pulls remote account changes repeatedly without duplicates', () async {
    final now = DateTime.utc(2026, 4, 13);
    await _seedProfileAndShop(database, now);
    remote.rows['accounts'] = [
      {
        'id': 'account-1',
        'user_id': 'user-1',
        'shop_id': 'shop-1',
        'name': 'Cash Counter',
        'type': 'cash',
        'color_hex': '#2F6B45',
        'sort_order': 0,
        'is_active': true,
        'is_system': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'client_updated_at': now.toIso8601String(),
      },
    ];

    await service.pullRemote(userId: 'user-1');
    await service.pullRemote(userId: 'user-1');

    final accounts = await database.select(database.accounts).get();
    final state = await (database.select(
      database.syncState,
    )..where((row) => row.key.equals('last_pull_at'))).getSingleOrNull();

    expect(accounts, hasLength(1));
    expect(accounts.single.name, 'Cash Counter');
    expect(state, isNotNull);
  });

  test('pull applies soft deletes locally', () async {
    final now = DateTime.utc(2026, 4, 13);
    final deletedAt = DateTime.utc(2026, 4, 14);
    await _seedProfileAndShop(database, now);
    remote.rows['accounts'] = [
      {
        'id': 'account-1',
        'user_id': 'user-1',
        'shop_id': 'shop-1',
        'name': 'Old Wallet',
        'type': 'custom',
        'is_active': true,
        'is_system': false,
        'created_at': now.toIso8601String(),
        'updated_at': deletedAt.toIso8601String(),
        'deleted_at': deletedAt.toIso8601String(),
        'client_updated_at': deletedAt.toIso8601String(),
      },
    ];

    await service.pullRemote(userId: 'user-1');

    final account = await database.select(database.accounts).getSingle();
    expect(account.deletedAt, isNotNull);
    expect(account.isActive, isFalse);
  });

  test('last-write-wins pull updates account names', () async {
    final now = DateTime.utc(2026, 4, 13);
    final later = DateTime.utc(2026, 4, 13, 1);
    await _seedProfileAndShop(database, now);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'account-1',
            userId: 'user-1',
            shopId: 'shop-1',
            name: 'Cash',
            type: 'cash',
            createdAt: now,
            updatedAt: now,
            clientUpdatedAt: now,
          ),
        );
    remote.rows['accounts'] = [
      {
        'id': 'account-1',
        'user_id': 'user-1',
        'shop_id': 'shop-1',
        'name': 'Main Cash',
        'type': 'cash',
        'is_active': true,
        'is_system': true,
        'created_at': now.toIso8601String(),
        'updated_at': later.toIso8601String(),
        'client_updated_at': later.toIso8601String(),
      },
    ];

    await service.pullRemote(userId: 'user-1');

    final account = await database.select(database.accounts).getSingle();
    expect(account.name, 'Main Cash');
  });

  test('fresh pull applies shops before memberships', () async {
    final now = DateTime.utc(2026, 4, 13);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'user-1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    remote.rows['shop_members'] = [
      {
        'id': 'member-1',
        'shop_id': 'shop-1',
        'user_id': 'user-1',
        'role': 'staff',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'client_updated_at': now.toIso8601String(),
      },
    ];
    remote.rows['shops'] = [
      {
        'id': 'shop-1',
        'user_id': 'owner-1',
        'name': 'Shared Shop',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
    ];

    await service.pullRemote(userId: 'user-1');

    final shops = await database.select(database.shops).get();
    final memberships = await database.select(database.shopMembers).get();
    expect(shops.single.name, 'Shared Shop');
    expect(memberships.single.shopId, 'shop-1');
  });

  test('pulls remote daily closings', () async {
    final now = DateTime.utc(2026, 4, 13);
    await _seedProfileAndShop(database, now);
    remote.rows['daily_closings'] = [
      {
        'id': 'close:shop-1:2026-04-13',
        'user_id': 'user-1',
        'shop_id': 'shop-1',
        'business_date': '2026-04-13',
        'total_in_paisa': 1000,
        'total_out_paisa': 200,
        'total_expense_paisa': 300,
        'net_change_paisa': 500,
        'closing_snapshot_json': {'snapshot_version': 1},
        'closed_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'client_updated_at': now.toIso8601String(),
      },
    ];

    await service.pullRemote(userId: 'user-1');

    final closing = await database.select(database.dailyClosings).getSingle();
    expect(closing.totalInPaisa, 1000);
    expect(closing.closingSnapshotJson, contains('snapshot_version'));
  });
}

Future<void> _seedProfileAndShop(AppDatabase database, DateTime now) async {
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(id: 'user-1', createdAt: now, updatedAt: now),
      );
  await database
      .into(database.shops)
      .insert(
        ShopsCompanion.insert(
          id: 'shop-1',
          userId: 'user-1',
          name: 'Demo Shop',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

class FakeRemoteStore implements SyncRemoteStore {
  final Map<String, List<Map<String, Object?>>> rows = {};
  final Map<String, List<Map<String, Object?>>> upserts = {};
  bool failUpserts = false;

  @override
  Future<void> upsert(String table, Map<String, Object?> payload) async {
    if (failUpserts) {
      throw StateError('remote failed');
    }
    upserts.putIfAbsent(table, () => []).add(payload);
  }

  @override
  Future<List<Map<String, Object?>>> selectUpdated({
    required String table,
    required String userId,
    required List<String> shopIds,
    required DateTime? updatedAfter,
  }) async {
    return [
      for (final row in rows[table] ?? const <Map<String, Object?>>[])
        if ((table == 'profiles'
                ? row['id'] == userId
                : table == 'shops'
                ? shopIds.contains(row['id'])
                : shopIds.contains(row['shop_id'])) &&
            (updatedAfter == null ||
                DateTime.parse(
                  row['updated_at']! as String,
                ).isAfter(updatedAfter)))
          row,
    ];
  }

  @override
  Future<List<Map<String, Object?>>> selectMemberships({
    required String userId,
    required DateTime? updatedAfter,
  }) async {
    return [
      for (final row in rows['shop_members'] ?? const <Map<String, Object?>>[])
        if (row['user_id'] == userId &&
            (updatedAfter == null ||
                DateTime.parse(
                  row['updated_at']! as String,
                ).isAfter(updatedAfter)))
          row,
    ];
  }

  @override
  Future<List<Map<String, Object?>>> selectShopsByIds({
    required List<String> shopIds,
  }) async {
    return [
      for (final row in rows['shops'] ?? const <Map<String, Object?>>[])
        if (shopIds.contains(row['id'])) row,
    ];
  }
}
