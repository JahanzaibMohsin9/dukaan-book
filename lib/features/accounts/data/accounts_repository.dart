import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/core/supabase/supabase_provider.dart';
import 'package:dukaan_book/core/time/business_date.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(
    database: ref.watch(appDatabaseProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    supabase: ref.watch(supabaseClientProvider),
  );
});

class AccountBalance {
  const AccountBalance({required this.account, required this.balancePaisa});

  final Account account;
  final int balancePaisa;

  Money get balance => Money.fromPaisa(balancePaisa);

  bool get isLowBalance {
    final threshold = account.lowBalanceThresholdPaisa;
    return threshold != null && balancePaisa <= threshold;
  }
}

class OpeningBalanceDraft {
  const OpeningBalanceDraft({required this.accountId, required this.amount});

  final String accountId;
  final Money amount;
}

class AccountWrite {
  const AccountWrite({
    required this.name,
    required this.type,
    required this.colorHex,
    this.lowBalanceThreshold,
  });

  final String name;
  final String type;
  final String colorHex;
  final Money? lowBalanceThreshold;
}

class AccountsRepository {
  const AccountsRepository({
    required this.database,
    required this.idGenerator,
    this.supabase,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final SupabaseClient? supabase;

  Stream<List<AccountBalance>> watchAccountBalances(
    String userId, {
    bool includeInactive = true,
  }) {
    final activeFilter = includeInactive ? '' : 'AND a.is_active = 1';
    return database
        .customSelect(
          '''
          SELECT a.*, COALESCE(SUM(l.amount_paisa), 0) AS balance_paisa
          FROM accounts AS a
          LEFT JOIN ledger_lines AS l
            ON l.account_id = a.id
            AND l.deleted_at IS NULL
            AND EXISTS (
              SELECT 1
              FROM ledger_transactions AS t
              WHERE t.id = l.transaction_id
                AND t.deleted_at IS NULL
            )
          WHERE a.shop_id = (${_activeShopSql(userId)})
            AND a.deleted_at IS NULL
            $activeFilter
          GROUP BY a.id
          ORDER BY a.is_active DESC, a.sort_order ASC, a.name COLLATE NOCASE ASC
          ''',
          variables: const [],
          readsFrom: {
            database.accounts,
            database.ledgerLines,
            database.ledgerTransactions,
            database.shops,
          },
        )
        .watch()
        .map(
          (rows) => rows.map((row) {
            return AccountBalance(
              account: database.accounts.map(row.data),
              balancePaisa: row.read<int>('balance_paisa'),
            );
          }).toList(),
        );
  }

  Future<List<AccountBalance>> getAccountBalances(String userId) {
    return watchAccountBalances(userId).first;
  }

  Future<Account?> getAccount(String accountId) {
    return (database.select(database.accounts)
          ..where((row) => row.id.equals(accountId))
          ..where((row) => row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<Shop?> getActiveShop(String userId) {
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
        .getSingleOrNull()
        .then((row) => row == null ? null : database.shops.map(row.data));
  }

  Future<void> postOpeningBalances({
    required String userId,
    required List<OpeningBalanceDraft> drafts,
  }) async {
    final shop = await _requireShop(userId);
    final ownerEquity = await _requireOwnerEquity(userId, shop.id);
    final balances = {
      for (final item in await getAccountBalances(userId))
        item.account.id: item.balancePaisa,
    };
    final deltaDrafts = [
      for (final draft in drafts)
        if (draft.accountId != ownerEquity.id)
          OpeningBalanceDraft(
            accountId: draft.accountId,
            amount: Money.fromPaisa(
              draft.amount.paisa - (balances[draft.accountId] ?? 0),
            ),
          ),
    ].where((draft) => !draft.amount.isZero).toList(growable: false);
    if (deltaDrafts.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final businessDate = BusinessDate.today(now);

    await database.transaction(() async {
      for (final draft in deltaDrafts) {
        final transactionId = idGenerator.next();
        await database
            .into(database.ledgerTransactions)
            .insert(
              LedgerTransactionsCompanion.insert(
                id: transactionId,
                userId: userId,
                shopId: shop.id,
                kind: 'opening_balance',
                businessDate: businessDate,
                note: const Value('Opening balance'),
                createdAt: now,
                updatedAt: now,
                clientUpdatedAt: now,
              ),
            );

        final accountLine = LedgerLinesCompanion.insert(
          id: idGenerator.next(),
          userId: userId,
          shopId: shop.id,
          transactionId: transactionId,
          accountId: draft.accountId,
          amountPaisa: draft.amount.paisa,
          memo: const Value('Opening balance'),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        );
        final equityLine = LedgerLinesCompanion.insert(
          id: idGenerator.next(),
          userId: userId,
          shopId: shop.id,
          transactionId: transactionId,
          accountId: ownerEquity.id,
          amountPaisa: -draft.amount.paisa,
          memo: const Value('Opening balance offset'),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        );

        await database.into(database.ledgerLines).insert(accountLine);
        await database.into(database.ledgerLines).insert(equityLine);
        await _queueOutbox(
          targetTableName: 'ledger_transactions',
          recordId: transactionId,
          operation: 'upsert',
          payload: {
            'id': transactionId,
            'user_id': userId,
            'shop_id': shop.id,
            'kind': 'opening_balance',
            'status': 'posted',
            'business_date': businessDate.toIso8601String(),
            'note': 'Opening balance',
            'client_updated_at': now.toIso8601String(),
          },
          now: now,
        );
        await _queueOutbox(
          targetTableName: 'ledger_lines',
          recordId: accountLine.id.value,
          operation: 'upsert',
          payload: _linePayload(accountLine),
          now: now,
        );
        await _queueOutbox(
          targetTableName: 'ledger_lines',
          recordId: equityLine.id.value,
          operation: 'upsert',
          payload: _linePayload(equityLine),
          now: now,
        );
      }
    });
  }

  Future<Account> createAccount({
    required String userId,
    required AccountWrite write,
  }) async {
    final shop = await _requireShop(userId);
    final now = DateTime.now().toUtc();
    final existing = await (database.select(
      database.accounts,
    )..where((row) => row.shopId.equals(shop.id))).get();
    final account = AccountsCompanion.insert(
      id: idGenerator.next(),
      userId: userId,
      shopId: shop.id,
      name: write.name.trim(),
      type: write.type.trim(),
      colorHex: Value(write.colorHex),
      sortOrder: Value(existing.length),
      isActive: const Value(true),
      isSystem: const Value(false),
      lowBalanceThresholdPaisa: Value(write.lowBalanceThreshold?.paisa),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    );

    await database.transaction(() async {
      await database.into(database.accounts).insert(account);
      await _queueAccountUpsert(account, now);
    });
    await _pushAccountToSupabase(account);

    return (await getAccount(account.id.value))!;
  }

  Future<void> updateAccount({
    required String accountId,
    required AccountWrite write,
  }) async {
    final existing = await getAccount(accountId);
    if (existing == null) {
      throw StateError('Account not found.');
    }
    final now = DateTime.now().toUtc();
    final companion = AccountsCompanion(
      id: Value(existing.id),
      userId: Value(existing.userId),
      shopId: Value(existing.shopId),
      name: Value(write.name.trim()),
      type: Value(write.type.trim()),
      colorHex: Value(write.colorHex),
      sortOrder: Value(existing.sortOrder),
      isActive: Value(existing.isActive),
      isSystem: Value(existing.isSystem),
      lowBalanceThresholdPaisa: Value(write.lowBalanceThreshold?.paisa),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
      deletedAt: Value(existing.deletedAt),
      clientUpdatedAt: Value(now),
    );

    await database.transaction(() async {
      await database.update(database.accounts).replace(companion);
      await _queueAccountUpsert(companion, now);
    });
    await _pushAccountToSupabase(companion);
  }

  Future<void> deactivateAccount(String accountId) async {
    final existing = await getAccount(accountId);
    if (existing == null) {
      throw StateError('Account not found.');
    }
    if (existing.isSystem) {
      throw StateError('System accounts cannot be deactivated.');
    }

    final now = DateTime.now().toUtc();
    final companion = AccountsCompanion(
      id: Value(existing.id),
      userId: Value(existing.userId),
      shopId: Value(existing.shopId),
      name: Value(existing.name),
      type: Value(existing.type),
      colorHex: Value(existing.colorHex),
      sortOrder: Value(existing.sortOrder),
      isActive: const Value(false),
      isSystem: Value(existing.isSystem),
      lowBalanceThresholdPaisa: Value(existing.lowBalanceThresholdPaisa),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
      deletedAt: const Value(null),
      clientUpdatedAt: Value(now),
    );

    await database.transaction(() async {
      await database.update(database.accounts).replace(companion);
      await _queueAccountUpsert(companion, now);
    });
    await _pushAccountToSupabase(companion);
  }

  Future<Shop> _requireShop(String userId) async {
    final shop = await getActiveShop(userId);
    if (shop == null) {
      throw StateError('Create a shop before managing accounts.');
    }
    return shop;
  }

  Future<Account> _requireOwnerEquity(String userId, String shopId) async {
    final account =
        await (database.select(database.accounts)
              ..where((row) => row.shopId.equals(shopId))
              ..where((row) => row.type.equals('owner_equity'))
              ..where((row) => row.deletedAt.isNull()))
            .getSingleOrNull();
    if (account == null) {
      throw StateError('Owner Equity account is required.');
    }
    return account;
  }

  Future<void> _queueAccountUpsert(AccountsCompanion account, DateTime now) {
    return _queueOutbox(
      targetTableName: 'accounts',
      recordId: account.id.value,
      operation: 'upsert',
      payload: _accountPayload(account),
      now: now,
    );
  }

  Future<void> _pushAccountToSupabase(AccountsCompanion account) async {
    final client = supabase;
    if (client == null) {
      return;
    }

    try {
      await client.from('accounts').upsert(_accountPayload(account));
    } catch (error) {
      debugPrint('Account sync deferred to outbox: $error');
    }
  }

  Future<void> _queueOutbox({
    required String targetTableName,
    required String recordId,
    required String operation,
    required Map<String, Object?> payload,
    required DateTime now,
  }) {
    return database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: idGenerator.next(),
            targetTableName: targetTableName,
            recordId: recordId,
            operation: operation,
            payloadJson: jsonEncode(payload),
            createdAt: now,
          ),
        );
  }

  static Map<String, Object?> _accountPayload(AccountsCompanion account) {
    return {
      'id': account.id.value,
      'user_id': account.userId.value,
      'shop_id': account.shopId.value,
      'name': account.name.value,
      'type': account.type.value,
      'color_hex': account.colorHex.value,
      'sort_order': account.sortOrder.value,
      'is_active': account.isActive.value,
      'is_system': account.isSystem.value,
      'low_balance_threshold_paisa': account.lowBalanceThresholdPaisa.value,
      'client_updated_at': account.clientUpdatedAt.value.toIso8601String(),
    };
  }

  static Map<String, Object?> _linePayload(LedgerLinesCompanion line) {
    return {
      'id': line.id.value,
      'user_id': line.userId.value,
      'shop_id': line.shopId.value,
      'transaction_id': line.transactionId.value,
      'account_id': line.accountId.value,
      'amount_paisa': line.amountPaisa.value,
      'memo': line.memo.value,
      'client_updated_at': line.clientUpdatedAt.value.toIso8601String(),
    };
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
