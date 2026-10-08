import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/supabase/supabase_provider.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SyncService(
    database: ref.watch(appDatabaseProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    remote: client == null ? null : SupabaseSyncRemoteStore(client),
  );
});

final syncStatusProvider = StreamProvider.autoDispose<SyncStatus>((ref) {
  return ref.watch(syncServiceProvider).watchStatus();
});

final autoSyncProvider = Provider<void>((ref) {
  final service = ref.watch(syncServiceProvider);
  final userId = ref.watch(authRepositoryProvider).currentUser?.id;
  if (userId == null) {
    return;
  }

  unawaited(service.syncNow(userId: userId));
  final subscription = Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((result) => result != ConnectivityResult.none)) {
      unawaited(service.syncNow(userId: userId));
    }
  });
  final statusSubscription = service.watchStatus().listen((status) {
    if (status.hasPendingWork && !status.isSyncing) {
      unawaited(service.syncNow(userId: userId));
    }
  });
  ref.onDispose(() {
    subscription.cancel();
    statusSubscription.cancel();
  });
});

class SyncStatus {
  const SyncStatus({
    required this.unsyncedCount,
    required this.isSyncing,
    this.lastSuccessfulSyncAt,
    this.lastError,
  });

  final int unsyncedCount;
  final bool isSyncing;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastError;

  bool get hasPendingWork => unsyncedCount > 0;
}

class SyncPushException implements Exception {
  const SyncPushException(this.failedCount);

  final int failedCount;

  @override
  String toString() {
    return '$failedCount pending sync ${failedCount == 1 ? 'item' : 'items'} failed to upload.';
  }
}

abstract class SyncRemoteStore {
  Future<void> upsert(String table, Map<String, Object?> payload);

  Future<List<Map<String, Object?>>> selectUpdated({
    required String table,
    required String userId,
    required List<String> shopIds,
    required DateTime? updatedAfter,
  });

  Future<List<Map<String, Object?>>> selectMemberships({
    required String userId,
    required DateTime? updatedAfter,
  });

  Future<List<Map<String, Object?>>> selectShopsByIds({
    required List<String> shopIds,
  });
}

class SupabaseSyncRemoteStore implements SyncRemoteStore {
  const SupabaseSyncRemoteStore(this.client);

  final SupabaseClient client;

  @override
  Future<void> upsert(String table, Map<String, Object?> payload) async {
    await client.from(table).upsert(payload);
  }

  @override
  Future<List<Map<String, Object?>>> selectUpdated({
    required String table,
    required String userId,
    required List<String> shopIds,
    required DateTime? updatedAfter,
  }) async {
    dynamic query = client.from(table).select();
    if (table == 'profiles') {
      query = query.eq('id', userId);
    } else if (table == 'shops') {
      if (shopIds.isEmpty) {
        return const [];
      }
      query = query.inFilter('id', shopIds);
    } else {
      if (shopIds.isEmpty) {
        return const [];
      }
      query = query.inFilter('shop_id', shopIds);
    }
    if (updatedAfter != null) {
      query = query.gt('updated_at', updatedAfter.toIso8601String());
    }

    final response = await query.order('updated_at');
    return [
      for (final row in response as List) Map<String, Object?>.from(row as Map),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> selectMemberships({
    required String userId,
    required DateTime? updatedAfter,
  }) async {
    dynamic query = client.from('shop_members').select();
    query = query.eq('user_id', userId);
    if (updatedAfter != null) {
      query = query.gt('updated_at', updatedAfter.toIso8601String());
    }

    final response = await query.order('updated_at');
    return [
      for (final row in response as List) Map<String, Object?>.from(row as Map),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> selectShopsByIds({
    required List<String> shopIds,
  }) async {
    if (shopIds.isEmpty) {
      return const [];
    }

    final response = await client
        .from('shops')
        .select()
        .inFilter('id', shopIds)
        .order('updated_at');
    return [
      for (final row in response as List) Map<String, Object?>.from(row as Map),
    ];
  }
}

class OutboxWriter {
  const OutboxWriter({required this.database, required this.idGenerator});

  final AppDatabase database;
  final IdGenerator idGenerator;

  Future<void> upsert({
    required String table,
    required String recordId,
    required Map<String, Object?> payload,
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now().toUtc();
    return database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: idGenerator.next(),
            targetTableName: table,
            recordId: recordId,
            operation: 'upsert',
            payloadJson: jsonEncode(payload),
            createdAt: createdAt,
          ),
        );
  }
}

class SyncService {
  SyncService({
    required this.database,
    required this.idGenerator,
    required this.remote,
  });

  static const _lastPullKey = 'last_pull_at';
  static const _lastSuccessfulSyncKey = 'last_successful_sync_at';
  static const _lastErrorKey = 'last_sync_error';
  static const _isSyncingKey = 'sync_is_running';

  static const _pullTables = [
    'profiles',
    'shop_members',
    'shops',
    'accounts',
    'expense_categories',
    'ledger_transactions',
    'ledger_lines',
    'daily_closings',
  ];

  final AppDatabase database;
  final IdGenerator idGenerator;
  final SyncRemoteStore? remote;

  OutboxWriter get outboxWriter {
    return OutboxWriter(database: database, idGenerator: idGenerator);
  }

  Stream<SyncStatus> watchStatus() {
    return database
        .customSelect(
          '''
          SELECT
            (SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL) AS unsynced_count,
            (SELECT value FROM sync_state WHERE key = ?) AS last_successful_sync_at,
            (SELECT value FROM sync_state WHERE key = ?) AS last_error,
            (SELECT value FROM sync_state WHERE key = ?) AS is_syncing
          ''',
          variables: [
            const Variable<String>(_lastSuccessfulSyncKey),
            const Variable<String>(_lastErrorKey),
            const Variable<String>(_isSyncingKey),
          ],
          readsFrom: {database.syncOutbox, database.syncState},
        )
        .watchSingle()
        .map((row) {
          final syncedAt = row.readNullable<String>('last_successful_sync_at');
          return SyncStatus(
            unsyncedCount: row.read<int>('unsynced_count'),
            lastSuccessfulSyncAt: syncedAt == null
                ? null
                : DateTime.tryParse(syncedAt),
            lastError: row.readNullable<String>('last_error'),
            isSyncing: row.readNullable<String>('is_syncing') == 'true',
          );
        });
  }

  Future<void> syncNow({required String userId}) async {
    final store = remote;
    if (store == null) {
      return;
    }

    await _setState(_isSyncingKey, 'true');
    try {
      await pushOutbox();
      await pullRemote(userId: userId);
      await _setState(
        _lastSuccessfulSyncKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await _deleteState(_lastErrorKey);
    } catch (error, stackTrace) {
      debugPrint('Sync failed: $error\n$stackTrace');
      await _setState(_lastErrorKey, error.toString());
    } finally {
      await _setState(_isSyncingKey, 'false');
    }
  }

  Future<void> pushOutbox() async {
    final store = remote;
    if (store == null) {
      return;
    }

    final pending =
        await (database.select(database.syncOutbox)
              ..where((row) => row.syncedAt.isNull())
              ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]))
            .get();

    var failedCount = 0;
    for (final item in pending) {
      final now = DateTime.now().toUtc();
      try {
        final payload = Map<String, Object?>.from(
          jsonDecode(item.payloadJson) as Map,
        );
        await store.upsert(item.targetTableName, payload);
        await (database.update(
          database.syncOutbox,
        )..where((row) => row.id.equals(item.id))).write(
          SyncOutboxCompanion(
            syncedAt: Value(now),
            lastAttemptAt: Value(now),
            lastError: const Value(null),
          ),
        );
      } catch (error) {
        failedCount += 1;
        await (database.update(
          database.syncOutbox,
        )..where((row) => row.id.equals(item.id))).write(
          SyncOutboxCompanion(
            attemptCount: Value(item.attemptCount + 1),
            lastAttemptAt: Value(now),
            lastError: Value(error.toString()),
          ),
        );
      }
    }

    if (failedCount > 0) {
      throw SyncPushException(failedCount);
    }
  }

  Future<void> pullRemote({required String userId}) async {
    final store = remote;
    if (store == null) {
      return;
    }

    final lastPullAt = await _getStateDate(_lastPullKey);
    final pullStartedAt = DateTime.now().toUtc();

    final membershipRows = await store.selectMemberships(
      userId: userId,
      updatedAfter: lastPullAt,
    );
    final remoteMembershipShopIds = {
      for (final row in membershipRows)
        if (row['shop_id'] != null) row['shop_id'].toString(),
    };
    final existingShopIds = await _localShopIdsForUser(userId);
    final bootstrapShopIds = remoteMembershipShopIds
        .where((shopId) => !existingShopIds.contains(shopId))
        .toList(growable: false);
    final bootstrapShops = await store.selectShopsByIds(
      shopIds: bootstrapShopIds,
    );
    for (final row in bootstrapShops) {
      await _applyRemoteRow('shops', row);
    }
    for (final row in membershipRows) {
      await _applyRemoteRow('shop_members', row);
    }

    for (final table in _pullTables) {
      if (table == 'shop_members') {
        continue;
      }
      final shopIds = await _localShopIdsForUser(userId);
      final rows = await store.selectUpdated(
        table: table,
        userId: userId,
        shopIds: shopIds,
        updatedAfter: lastPullAt,
      );
      for (final row in rows) {
        await _applyRemoteRow(table, row);
      }
    }

    await _setState(_lastPullKey, pullStartedAt.toIso8601String());
  }

  Future<void> _applyRemoteRow(String table, Map<String, Object?> row) {
    return switch (table) {
      'profiles' =>
        database
            .into(database.profiles)
            .insertOnConflictUpdate(_profileCompanion(row)),
      'shop_members' =>
        database
            .into(database.shopMembers)
            .insertOnConflictUpdate(_memberCompanion(row)),
      'shops' => _applyShopRow(row),
      'accounts' =>
        database
            .into(database.accounts)
            .insertOnConflictUpdate(_accountCompanion(row)),
      'expense_categories' =>
        database
            .into(database.expenseCategories)
            .insertOnConflictUpdate(_categoryCompanion(row)),
      'ledger_transactions' =>
        database
            .into(database.ledgerTransactions)
            .insertOnConflictUpdate(_transactionCompanion(row)),
      'ledger_lines' =>
        database
            .into(database.ledgerLines)
            .insertOnConflictUpdate(_lineCompanion(row)),
      'daily_closings' =>
        database
            .into(database.dailyClosings)
            .insertOnConflictUpdate(_closingCompanion(row)),
      _ => Future.value(),
    };
  }

  Future<void> _applyShopRow(Map<String, Object?> row) async {
    final ownerId = row['user_id'] as String;
    final existingProfile = await (database.select(
      database.profiles,
    )..where((profile) => profile.id.equals(ownerId))).getSingleOrNull();
    if (existingProfile == null) {
      final now = DateTime.now().toUtc();
      await database
          .into(database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: ownerId,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await database
        .into(database.shops)
        .insertOnConflictUpdate(_shopCompanion(row));
  }

  Future<DateTime?> _getStateDate(String key) async {
    final value = await (database.select(
      database.syncState,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return value == null ? null : DateTime.tryParse(value.value);
  }

  Future<List<String>> _localShopIdsForUser(String userId) async {
    final memberships =
        await (database.select(database.shopMembers)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.deletedAt.isNull()))
            .get();
    final ownShops =
        await (database.select(database.shops)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.deletedAt.isNull()))
            .get();
    return {
      for (final membership in memberships) membership.shopId,
      for (final shop in ownShops) shop.id,
    }.toList(growable: false);
  }

  Future<void> _setState(String key, String value) {
    final now = DateTime.now().toUtc();
    return database
        .into(database.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(key: key, value: value, updatedAt: now),
        );
  }

  Future<void> _deleteState(String key) {
    return (database.delete(
      database.syncState,
    )..where((row) => row.key.equals(key))).go();
  }

  static ProfilesCompanion _profileCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return ProfilesCompanion(
      id: Value(row['id'] as String),
      fullName: Value(row['full_name'] as String?),
      phone: Value(row['phone'] as String?),
      preferredLanguage: Value((row['preferred_language'] as String?) ?? 'en'),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
    );
  }

  static ShopsCompanion _shopCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return ShopsCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      name: Value(row['name'] as String),
      city: Value(row['city'] as String?),
      phone: Value(row['phone'] as String?),
      timezone: Value((row['timezone'] as String?) ?? 'Asia/Karachi'),
      dayCloseTime: Value(_timeText(row['day_close_time']) ?? '21:00'),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
    );
  }

  static ShopMembersCompanion _memberCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return ShopMembersCompanion(
      id: Value(row['id'] as String),
      shopId: Value(row['shop_id'] as String),
      userId: Value(row['user_id'] as String),
      role: Value((row['role'] as String?) ?? 'staff'),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static AccountsCompanion _accountCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    final deletedAt = _date(row['deleted_at']);
    return AccountsCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      shopId: Value(row['shop_id'] as String),
      name: Value(row['name'] as String),
      type: Value(row['type'] as String),
      colorHex: Value(row['color_hex'] as String?),
      sortOrder: Value(_int(row['sort_order']) ?? 0),
      isActive: Value(
        deletedAt == null && ((row['is_active'] as bool?) ?? true),
      ),
      isSystem: Value((row['is_system'] as bool?) ?? false),
      lowBalanceThresholdPaisa: Value(_int(row['low_balance_threshold_paisa'])),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(deletedAt),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static ExpenseCategoriesCompanion _categoryCompanion(
    Map<String, Object?> row,
  ) {
    final now = DateTime.now().toUtc();
    return ExpenseCategoriesCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      shopId: Value(row['shop_id'] as String),
      name: Value(row['name'] as String),
      icon: Value(row['icon'] as String?),
      sortOrder: Value(_int(row['sort_order']) ?? 0),
      isSystem: Value((row['is_system'] as bool?) ?? false),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static LedgerTransactionsCompanion _transactionCompanion(
    Map<String, Object?> row,
  ) {
    final now = DateTime.now().toUtc();
    return LedgerTransactionsCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      shopId: Value(row['shop_id'] as String),
      kind: Value(row['kind'] as String),
      status: Value((row['status'] as String?) ?? 'posted'),
      businessDate: Value(_businessDate(row['business_date']) ?? now),
      note: Value(row['note'] as String?),
      externalRef: Value(row['external_ref'] as String?),
      reversedTransactionId: Value(row['reversed_transaction_id'] as String?),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static LedgerLinesCompanion _lineCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return LedgerLinesCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      shopId: Value(row['shop_id'] as String),
      transactionId: Value(row['transaction_id'] as String),
      accountId: Value(row['account_id'] as String),
      amountPaisa: Value(_int(row['amount_paisa']) ?? 0),
      memo: Value(row['memo'] as String?),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static DailyClosingsCompanion _closingCompanion(Map<String, Object?> row) {
    final now = DateTime.now().toUtc();
    return DailyClosingsCompanion(
      id: Value(row['id'] as String),
      userId: Value(row['user_id'] as String),
      shopId: Value(row['shop_id'] as String),
      businessDate: Value(_businessDate(row['business_date']) ?? now),
      totalInPaisa: Value(_int(row['total_in_paisa']) ?? 0),
      totalOutPaisa: Value(_int(row['total_out_paisa']) ?? 0),
      totalExpensePaisa: Value(_int(row['total_expense_paisa']) ?? 0),
      netChangePaisa: Value(_int(row['net_change_paisa']) ?? 0),
      closingSnapshotJson: Value(_jsonText(row['closing_snapshot_json'])),
      closedAt: Value(_date(row['closed_at']) ?? now),
      reopenedAt: Value(_date(row['reopened_at'])),
      note: Value(row['note'] as String?),
      createdAt: Value(_date(row['created_at']) ?? now),
      updatedAt: Value(_date(row['updated_at']) ?? now),
      deletedAt: Value(_date(row['deleted_at'])),
      clientUpdatedAt: Value(_date(row['client_updated_at']) ?? now),
    );
  }

  static DateTime? _date(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static DateTime? _businessDate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final parts = value.toString().split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2].substring(0, 2)),
      );
    }
    return _date(value);
  }

  static int? _int(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static String? _timeText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  static String _jsonText(Object? value) {
    if (value == null) {
      return '{}';
    }
    if (value is String) {
      return value;
    }
    return jsonEncode(value);
  }
}
