import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/time/business_date.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dailyReportRepositoryProvider = Provider<DailyReportRepository>((ref) {
  return DailyReportRepository(
    database: ref.watch(appDatabaseProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

final dailyReportByDateProvider = StreamProvider.autoDispose
    .family<DailyReport, DateTime>((ref, businessDate) {
      final userId = ref.watch(authRepositoryProvider).currentUser?.id;
      final normalizedDate = DateTime(
        businessDate.year,
        businessDate.month,
        businessDate.day,
      );
      if (userId == null) {
        return Stream.value(DailyReport.empty(normalizedDate));
      }

      return ref
          .watch(dailyReportRepositoryProvider)
          .watchDailyReport(userId: userId, businessDate: normalizedDate);
    });

final dailyReportProvider = StreamProvider.autoDispose<DailyReport>((ref) {
  final userId = ref.watch(authRepositoryProvider).currentUser?.id;
  final businessDate = BusinessDate.today();
  if (userId == null) {
    return Stream.value(DailyReport.empty(businessDate));
  }

  return ref
      .watch(dailyReportRepositoryProvider)
      .watchDailyReport(userId: userId, businessDate: businessDate);
});

class DailyReport {
  const DailyReport({
    required this.businessDate,
    required this.isClosed,
    required this.closedAt,
    required this.accounts,
    required this.transactions,
    required this.inflowPaisa,
    required this.outflowPaisa,
    required this.expensePaisa,
    required this.transferPaisa,
    required this.serviceChargePaisa,
    required this.netChangePaisa,
    required this.expensesByCategory,
    required this.hasUnsyncedEntries,
  });

  factory DailyReport.empty(DateTime businessDate) {
    return DailyReport(
      businessDate: businessDate,
      isClosed: false,
      closedAt: null,
      accounts: const [],
      transactions: const [],
      inflowPaisa: 0,
      outflowPaisa: 0,
      expensePaisa: 0,
      transferPaisa: 0,
      serviceChargePaisa: 0,
      netChangePaisa: 0,
      expensesByCategory: const [],
      hasUnsyncedEntries: false,
    );
  }

  final DateTime businessDate;
  final bool isClosed;
  final DateTime? closedAt;
  final List<DailyReportAccountBalance> accounts;
  final List<DailyReportTransactionItem> transactions;
  final int inflowPaisa;
  final int outflowPaisa;
  final int expensePaisa;
  final int transferPaisa;
  final int serviceChargePaisa;
  final int netChangePaisa;
  final List<ExpenseCategoryTotal> expensesByCategory;
  final bool hasUnsyncedEntries;
}

class DailyReportAccountBalance {
  const DailyReportAccountBalance({
    required this.accountId,
    required this.accountName,
    required this.accountType,
    required this.isActive,
    required this.openingBalancePaisa,
    required this.closingBalancePaisa,
  });

  final String accountId;
  final String accountName;
  final String accountType;
  final bool isActive;
  final int openingBalancePaisa;
  final int closingBalancePaisa;

  int get movementPaisa => closingBalancePaisa - openingBalancePaisa;
}

class ExpenseCategoryTotal {
  const ExpenseCategoryTotal({
    required this.categoryName,
    required this.amountPaisa,
  });

  final String categoryName;
  final int amountPaisa;
}

class DailyReportTransactionItem {
  const DailyReportTransactionItem({
    required this.id,
    required this.kind,
    required this.businessDate,
    required this.createdAt,
    required this.amountPaisa,
    required this.lineCount,
    this.note,
    this.primaryAccountName,
  });

  final String id;
  final String kind;
  final DateTime businessDate;
  final DateTime createdAt;
  final int amountPaisa;
  final int lineCount;
  final String? note;
  final String? primaryAccountName;
}

class DailyReportTransactionLine {
  const DailyReportTransactionLine({
    required this.accountId,
    required this.accountName,
    required this.amountPaisa,
    this.memo,
  });

  final String accountId;
  final String accountName;
  final int amountPaisa;
  final String? memo;
}

class DailyReportRepository {
  DailyReportRepository({required this.database, IdGenerator? idGenerator})
    : idGenerator = idGenerator ?? IdGenerator();

  final AppDatabase database;
  final IdGenerator idGenerator;

  Stream<DailyReport> watchDailyReport({
    required String userId,
    required DateTime businessDate,
  }) {
    return database
        .customSelect(
          '''
          SELECT
            (SELECT COUNT(*) FROM ledger_transactions WHERE shop_id = (${_activeShopSql(userId)})) AS tx_count,
            (SELECT COUNT(*) FROM ledger_lines WHERE shop_id = (${_activeShopSql(userId)})) AS line_count,
            (SELECT COUNT(*) FROM accounts WHERE shop_id = (${_activeShopSql(userId)}) AND deleted_at IS NULL) AS account_count,
            (SELECT COUNT(*) FROM daily_closings WHERE shop_id = (${_activeShopSql(userId)}) AND business_date = ? AND deleted_at IS NULL) AS closing_count,
            (SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL) AS unsynced_count
          ''',
          variables: [Variable<DateTime>(businessDate)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.dailyClosings,
            database.shops,
            database.syncOutbox,
          },
        )
        .watchSingle()
        .asyncMap(
          (_) => getDailyReport(userId: userId, businessDate: businessDate),
        );
  }

  Future<DailyReport> getDailyReport({
    required String userId,
    required DateTime businessDate,
  }) async {
    final reportDate = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );

    final closing = await _loadClosing(
      userId: userId,
      businessDate: reportDate,
    );
    if (closing != null && closing.reopenedAt == null) {
      return _dailyReportFromSnapshot(
        snapshotJson: closing.closingSnapshotJson,
        fallbackDate: reportDate,
        closedAt: closing.closedAt,
      );
    }

    return _buildLiveDailyReport(userId: userId, businessDate: reportDate);
  }

  Future<void> closeDay({
    required String userId,
    required DateTime businessDate,
    String? note,
  }) async {
    final reportDate = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    final existing = await _loadClosing(
      userId: userId,
      businessDate: reportDate,
    );
    if (existing != null && existing.reopenedAt == null) {
      throw const DayAlreadyClosedException();
    }

    final liveReport = await _buildLiveDailyReport(
      userId: userId,
      businessDate: reportDate,
    );
    final shop = await _requireShop(userId);
    final now = DateTime.now().toUtc();
    final snapshotJson = _dailyReportSnapshotJson(liveReport, closedAt: now);

    if (existing == null) {
      final id = 'close:${shop.id}:${BusinessDate.toIsoDate(reportDate)}';
      final closing = DailyClosingsCompanion.insert(
        id: id,
        userId: userId,
        shopId: shop.id,
        businessDate: reportDate,
        totalInPaisa: liveReport.inflowPaisa,
        totalOutPaisa: liveReport.outflowPaisa,
        totalExpensePaisa: liveReport.expensePaisa,
        netChangePaisa: liveReport.netChangePaisa,
        closingSnapshotJson: snapshotJson,
        closedAt: now,
        reopenedAt: const Value(null),
        note: Value(_nullableTrim(note)),
        createdAt: now,
        updatedAt: now,
        clientUpdatedAt: now,
      );
      await database.transaction(() async {
        await database.into(database.dailyClosings).insert(closing);
        await _queueClosingUpsert(closing, now);
      });
      return;
    }

    final closing = DailyClosingsCompanion(
      id: Value(existing.id),
      userId: Value(existing.userId),
      shopId: Value(existing.shopId),
      businessDate: Value(existing.businessDate),
      totalInPaisa: Value(liveReport.inflowPaisa),
      totalOutPaisa: Value(liveReport.outflowPaisa),
      totalExpensePaisa: Value(liveReport.expensePaisa),
      netChangePaisa: Value(liveReport.netChangePaisa),
      closingSnapshotJson: Value(snapshotJson),
      closedAt: Value(now),
      reopenedAt: const Value(null),
      note: Value(_nullableTrim(note)),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
      deletedAt: Value(existing.deletedAt),
      clientUpdatedAt: Value(now),
    );
    await database.transaction(() async {
      await database.update(database.dailyClosings).replace(closing);
      await _queueClosingUpsert(closing, now);
    });
  }

  Future<void> reopenDay({
    required String userId,
    required DateTime businessDate,
    String? note,
  }) async {
    final reportDate = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    final closing = await _loadClosing(
      userId: userId,
      businessDate: reportDate,
    );
    if (closing == null || closing.reopenedAt != null) {
      throw const DayNotClosedException();
    }

    final now = DateTime.now().toUtc();
    final reopenNote = _mergeNotes(closing.note, note);
    final updated = DailyClosingsCompanion(
      id: Value(closing.id),
      userId: Value(closing.userId),
      shopId: Value(closing.shopId),
      businessDate: Value(closing.businessDate),
      totalInPaisa: Value(closing.totalInPaisa),
      totalOutPaisa: Value(closing.totalOutPaisa),
      totalExpensePaisa: Value(closing.totalExpensePaisa),
      netChangePaisa: Value(closing.netChangePaisa),
      closingSnapshotJson: Value(closing.closingSnapshotJson),
      closedAt: Value(closing.closedAt),
      reopenedAt: Value(now),
      note: Value(reopenNote),
      createdAt: Value(closing.createdAt),
      updatedAt: Value(now),
      deletedAt: Value(closing.deletedAt),
      clientUpdatedAt: Value(now),
    );
    await database.transaction(() async {
      await database.update(database.dailyClosings).replace(updated);
      await _queueClosingUpsert(updated, now);
    });
  }

  Future<DailyReport> _buildLiveDailyReport({
    required String userId,
    required DateTime businessDate,
  }) async {
    final accountRows = await _loadAccountBalances(
      userId: userId,
      businessDate: businessDate,
    );
    final totals = await _loadTotals(
      userId: userId,
      businessDate: businessDate,
    );
    final transactions = await _loadTransactions(
      userId: userId,
      businessDate: businessDate,
    );
    final expenseRows = await _loadExpensesByCategory(
      userId: userId,
      businessDate: businessDate,
    );
    final hasUnsynced = await _hasUnsyncedOutbox();

    return DailyReport(
      businessDate: businessDate,
      isClosed: false,
      closedAt: null,
      accounts: accountRows,
      transactions: transactions,
      inflowPaisa: totals.inflow,
      outflowPaisa: totals.outflow,
      expensePaisa: totals.expense,
      transferPaisa: totals.transfer,
      serviceChargePaisa: totals.serviceCharge,
      netChangePaisa: totals.netChange,
      expensesByCategory: expenseRows,
      hasUnsyncedEntries: hasUnsynced,
    );
  }

  Future<DailyClosing?> _loadClosing({
    required String userId,
    required DateTime businessDate,
  }) {
    return database
        .customSelect(
          '''
          SELECT *
          FROM daily_closings
          WHERE shop_id = (${_activeShopSql(userId)})
            AND business_date = ?
            AND deleted_at IS NULL
          LIMIT 1
          ''',
          variables: [Variable<DateTime>(businessDate)],
          readsFrom: {database.dailyClosings, database.shops},
        )
        .getSingleOrNull()
        .then(
          (row) => row == null ? null : database.dailyClosings.map(row.data),
        );
  }

  Future<Shop> _requireShop(String userId) async {
    final row = await database
        .customSelect(
          '''
          SELECT *
          FROM shops
          WHERE id = (${_activeShopSql(userId)})
          LIMIT 1
          ''',
          readsFrom: {database.shops, database.shopMembers},
        )
        .getSingleOrNull();
    final shop = row == null ? null : database.shops.map(row.data);
    if (shop == null) {
      throw const DayClosingException('No active shop found for this user.');
    }
    return shop;
  }

  DailyReport _dailyReportFromSnapshot({
    required String snapshotJson,
    required DateTime fallbackDate,
    required DateTime closedAt,
  }) {
    final decoded = Map<String, Object?>.from(
      jsonDecode(snapshotJson) as Map<String, Object?>,
    );
    final snapshotDate =
        _snapshotDate(decoded['business_date']) ?? fallbackDate;

    final accountItems = (decoded['accounts'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) {
          final map = Map<String, Object?>.from(row.cast<String, Object?>());
          return DailyReportAccountBalance(
            accountId: map['id'] as String? ?? '',
            accountName: map['name'] as String? ?? '',
            accountType: map['type'] as String? ?? 'custom',
            isActive: map['is_active'] as bool? ?? true,
            openingBalancePaisa: _asInt(map['opening_balance_paisa']),
            closingBalancePaisa: _asInt(map['closing_balance_paisa']),
          );
        })
        .toList(growable: false);

    final expenseItems =
        (decoded['expenses_by_category'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) {
              final map = Map<String, Object?>.from(
                row.cast<String, Object?>(),
              );
              return ExpenseCategoryTotal(
                categoryName: map['category_name'] as String? ?? '',
                amountPaisa: _asInt(map['amount_paisa']),
              );
            })
            .toList(growable: false);

    final transactionItems =
        (decoded['transactions'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) {
              final map = Map<String, Object?>.from(
                row.cast<String, Object?>(),
              );
              return DailyReportTransactionItem(
                id: map['id'] as String? ?? '',
                kind: map['kind'] as String? ?? 'unknown',
                businessDate:
                    _snapshotDate(map['business_date']) ?? snapshotDate,
                createdAt: _snapshotDateTime(map['created_at']) ?? snapshotDate,
                amountPaisa: _asInt(map['amount_paisa']),
                lineCount: _asInt(map['line_count']),
                note: map['note'] as String?,
                primaryAccountName: map['primary_account_name'] as String?,
              );
            })
            .toList(growable: false);

    return DailyReport(
      businessDate: snapshotDate,
      isClosed: true,
      closedAt: closedAt,
      accounts: accountItems,
      transactions: transactionItems,
      inflowPaisa: _asInt(decoded['inflow_paisa']),
      outflowPaisa: _asInt(decoded['outflow_paisa']),
      expensePaisa: _asInt(decoded['expense_paisa']),
      transferPaisa: _asInt(decoded['transfer_paisa']),
      serviceChargePaisa: _asInt(decoded['service_charge_paisa']),
      netChangePaisa: _asInt(decoded['net_change_paisa']),
      expensesByCategory: expenseItems,
      hasUnsyncedEntries: decoded['has_unsynced_entries'] as bool? ?? false,
    );
  }

  String _dailyReportSnapshotJson(
    DailyReport report, {
    required DateTime closedAt,
  }) {
    final json = <String, Object?>{
      'snapshot_version': 1,
      'business_date': report.businessDate.toIso8601String(),
      'closed_at': closedAt.toIso8601String(),
      'inflow_paisa': report.inflowPaisa,
      'outflow_paisa': report.outflowPaisa,
      'expense_paisa': report.expensePaisa,
      'transfer_paisa': report.transferPaisa,
      'service_charge_paisa': report.serviceChargePaisa,
      'net_change_paisa': report.netChangePaisa,
      'has_unsynced_entries': report.hasUnsyncedEntries,
      'accounts': [
        for (final account in report.accounts)
          {
            'id': account.accountId,
            'name': account.accountName,
            'type': account.accountType,
            'is_active': account.isActive,
            'opening_balance_paisa': account.openingBalancePaisa,
            'closing_balance_paisa': account.closingBalancePaisa,
          },
      ],
      'expenses_by_category': [
        for (final item in report.expensesByCategory)
          {
            'category_name': item.categoryName,
            'amount_paisa': item.amountPaisa,
          },
      ],
      'transactions': [
        for (final item in report.transactions)
          {
            'id': item.id,
            'kind': item.kind,
            'business_date': item.businessDate.toIso8601String(),
            'created_at': item.createdAt.toIso8601String(),
            'amount_paisa': item.amountPaisa,
            'line_count': item.lineCount,
            'note': item.note,
            'primary_account_name': item.primaryAccountName,
          },
      ],
    };
    return jsonEncode(json);
  }

  static DateTime? _snapshotDate(Object? value) {
    final parsed = _snapshotDateTime(value);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime? _snapshotDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _mergeNotes(String? existing, String? incoming) {
    final current = _nullableTrim(existing);
    final extra = _nullableTrim(incoming);
    if (extra == null) {
      return current;
    }
    if (current == null) {
      return 'Reopened: $extra';
    }
    return '$current | Reopened: $extra';
  }

  Future<List<DailyReportTransactionLine>> getTransactionLines({
    required String transactionId,
  }) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        l.account_id,
        a.name AS account_name,
        l.amount_paisa,
        l.memo
      FROM ledger_lines AS l
      INNER JOIN accounts AS a ON a.id = l.account_id
      INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
      WHERE l.transaction_id = ?
        AND t.deleted_at IS NULL
        AND l.deleted_at IS NULL
      ORDER BY ABS(l.amount_paisa) DESC, a.name COLLATE NOCASE ASC
      ''',
          variables: [Variable<String>(transactionId)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
          },
        )
        .get();

    return rows
        .map(
          (row) => DailyReportTransactionLine(
            accountId: row.read<String>('account_id'),
            accountName: row.read<String>('account_name'),
            amountPaisa: row.read<int>('amount_paisa'),
            memo: row.readNullable<String>('memo'),
          ),
        )
        .toList(growable: false);
  }

  Future<String?> getActiveShopName({required String userId}) async {
    final row = await database
        .customSelect(
          '''
          SELECT *
          FROM shops
          WHERE id = (${_activeShopSql(userId)})
          LIMIT 1
          ''',
          readsFrom: {database.shops, database.shopMembers},
        )
        .getSingleOrNull();
    final shop = row == null ? null : database.shops.map(row.data);
    return shop?.name;
  }

  Future<List<DailyReportAccountBalance>> _loadAccountBalances({
    required String userId,
    required DateTime businessDate,
  }) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        a.id,
        a.name,
        a.type,
        a.is_active,
        COALESCE((
          SELECT SUM(l.amount_paisa)
          FROM ledger_lines AS l
          INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
          WHERE l.account_id = a.id
            AND t.shop_id = (${_activeShopSql(userId)})
            AND t.business_date < ?
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
        ), 0) AS opening_balance_paisa,
        COALESCE((
          SELECT SUM(l.amount_paisa)
          FROM ledger_lines AS l
          INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
          WHERE l.account_id = a.id
            AND t.shop_id = (${_activeShopSql(userId)})
            AND t.business_date <= ?
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
        ), 0) AS closing_balance_paisa
      FROM accounts AS a
      WHERE a.shop_id = (${_activeShopSql(userId)})
        AND a.deleted_at IS NULL
        AND a.type NOT IN ('expense_bucket', 'owner_equity')
      ORDER BY a.sort_order ASC, a.name COLLATE NOCASE ASC
      ''',
          variables: [
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
          ],
          readsFrom: {
            database.accounts,
            database.ledgerTransactions,
            database.ledgerLines,
            database.shops,
          },
        )
        .get();

    return rows
        .map(
          (row) => DailyReportAccountBalance(
            accountId: row.read<String>('id'),
            accountName: row.read<String>('name'),
            accountType: row.read<String>('type'),
            isActive: row.read<bool>('is_active'),
            openingBalancePaisa: row.read<int>('opening_balance_paisa'),
            closingBalancePaisa: row.read<int>('closing_balance_paisa'),
          ),
        )
        .toList(growable: false);
  }

  Future<_ReportTotals> _loadTotals({
    required String userId,
    required DateTime businessDate,
  }) async {
    final row = await database
        .customSelect(
          '''
          SELECT
            COALESCE((
              SELECT SUM(l.amount_paisa)
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'cash_in'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND l.amount_paisa > 0
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS inflow_paisa,
            COALESCE((
              SELECT SUM(ABS(l.amount_paisa))
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'cash_out'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND l.amount_paisa < 0
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS outflow_paisa,
            COALESCE((
              SELECT SUM(ABS(l.amount_paisa))
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'expense'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND l.amount_paisa < 0
                AND a.type != 'expense_bucket'
            ), 0) AS expense_paisa,
            COALESCE((
              SELECT SUM(ABS(l.amount_paisa))
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'transfer'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND l.amount_paisa < 0
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS transfer_paisa,
            COALESCE((
              SELECT SUM(l.amount_paisa)
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'transfer'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS service_charge_paisa,
            COALESCE((
              SELECT SUM(CASE WHEN l.amount_paisa > 0 THEN l.amount_paisa ELSE 0 END)
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'adjustment'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS adjustment_in_paisa,
            COALESCE((
              SELECT SUM(ABS(CASE WHEN l.amount_paisa < 0 THEN l.amount_paisa ELSE 0 END))
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.kind = 'adjustment'
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS adjustment_out_paisa,
            COALESCE((
              SELECT SUM(l.amount_paisa)
              FROM ledger_lines AS l
              INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
              INNER JOIN accounts AS a ON a.id = l.account_id
              WHERE t.shop_id = (${_activeShopSql(userId)})
                AND t.business_date = ?
                AND t.deleted_at IS NULL
                AND l.deleted_at IS NULL
                AND a.type NOT IN ('expense_bucket', 'owner_equity')
            ), 0) AS net_change_paisa
          ''',
          variables: [
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
            Variable<DateTime>(businessDate),
          ],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .getSingle();

    final inflow =
        row.read<int>('inflow_paisa') + row.read<int>('adjustment_in_paisa');
    final outflow =
        row.read<int>('outflow_paisa') + row.read<int>('adjustment_out_paisa');
    return _ReportTotals(
      inflow: inflow,
      outflow: outflow,
      expense: row.read<int>('expense_paisa'),
      transfer: row.read<int>('transfer_paisa'),
      serviceCharge: row.read<int>('service_charge_paisa'),
      netChange: row.read<int>('net_change_paisa'),
    );
  }

  Future<List<ExpenseCategoryTotal>> _loadExpensesByCategory({
    required String userId,
    required DateTime businessDate,
  }) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        REPLACE(expense_account.name, 'Expense: ', '') AS category_name,
        SUM(ABS(payment_line.amount_paisa)) AS total_paisa
      FROM ledger_transactions AS t
      INNER JOIN ledger_lines AS payment_line
        ON payment_line.transaction_id = t.id
      INNER JOIN accounts AS payment_account
        ON payment_account.id = payment_line.account_id
      INNER JOIN ledger_lines AS expense_line
        ON expense_line.transaction_id = t.id
      INNER JOIN accounts AS expense_account
        ON expense_account.id = expense_line.account_id
      WHERE t.shop_id = (${_activeShopSql(userId)})
        AND t.kind = 'expense'
        AND t.business_date = ?
        AND t.deleted_at IS NULL
        AND payment_line.deleted_at IS NULL
        AND expense_line.deleted_at IS NULL
        AND payment_line.amount_paisa < 0
        AND payment_account.type != 'expense_bucket'
        AND expense_account.type = 'expense_bucket'
      GROUP BY category_name
      ORDER BY total_paisa DESC, category_name COLLATE NOCASE ASC
      ''',
          variables: [Variable<DateTime>(businessDate)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .get();

    return rows
        .map(
          (row) => ExpenseCategoryTotal(
            categoryName: row.read<String>('category_name'),
            amountPaisa: row.read<int>('total_paisa'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DailyReportTransactionItem>> _loadTransactions({
    required String userId,
    required DateTime businessDate,
  }) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        t.id,
        t.kind,
        t.business_date,
        t.created_at,
        t.note,
        CASE
          WHEN t.kind = 'cash_in' THEN MAX(l.amount_paisa)
          WHEN t.kind = 'cash_out' THEN MIN(l.amount_paisa)
          WHEN t.kind = 'expense' THEN MIN(l.amount_paisa)
          WHEN t.kind = 'transfer' THEN SUM(l.amount_paisa)
          ELSE SUM(l.amount_paisa)
        END AS display_amount_paisa,
        COUNT(l.id) AS line_count,
        (
          SELECT a2.name
          FROM ledger_lines AS l2
          INNER JOIN accounts AS a2 ON a2.id = l2.account_id
          WHERE l2.transaction_id = t.id
            AND l2.deleted_at IS NULL
            AND a2.type != 'expense_bucket'
          ORDER BY ABS(l2.amount_paisa) DESC
          LIMIT 1
        ) AS primary_account_name
      FROM ledger_transactions AS t
      INNER JOIN ledger_lines AS l ON l.transaction_id = t.id
      WHERE t.shop_id = (${_activeShopSql(userId)})
        AND t.business_date = ?
        AND t.deleted_at IS NULL
        AND l.deleted_at IS NULL
      GROUP BY t.id
      ORDER BY t.created_at DESC
      ''',
          variables: [Variable<DateTime>(businessDate)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .get();

    return rows
        .map(
          (row) => DailyReportTransactionItem(
            id: row.read<String>('id'),
            kind: row.read<String>('kind'),
            businessDate: row.read<DateTime>('business_date'),
            createdAt: row.read<DateTime>('created_at'),
            note: row.readNullable<String>('note'),
            amountPaisa: row.read<int>('display_amount_paisa'),
            lineCount: row.read<int>('line_count'),
            primaryAccountName: row.readNullable<String>(
              'primary_account_name',
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> _hasUnsyncedOutbox() async {
    final row = await database
        .customSelect(
          '''
          SELECT COUNT(*) AS unsynced_count
          FROM sync_outbox
          WHERE synced_at IS NULL
          ''',
          readsFrom: {database.syncOutbox},
        )
        .getSingle();
    return row.read<int>('unsynced_count') > 0;
  }

  Future<void> _queueClosingUpsert(
    DailyClosingsCompanion closing,
    DateTime now,
  ) {
    return database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: idGenerator.next(),
            targetTableName: 'daily_closings',
            recordId: closing.id.value,
            operation: 'upsert',
            payloadJson: jsonEncode(_closingPayload(closing)),
            createdAt: now,
          ),
        );
  }

  static Map<String, Object?> _closingPayload(DailyClosingsCompanion closing) {
    return {
      'id': closing.id.value,
      'user_id': closing.userId.value,
      'shop_id': closing.shopId.value,
      'business_date': BusinessDate.toIsoDate(closing.businessDate.value),
      'total_in_paisa': closing.totalInPaisa.value,
      'total_out_paisa': closing.totalOutPaisa.value,
      'total_expense_paisa': closing.totalExpensePaisa.value,
      'net_change_paisa': closing.netChangePaisa.value,
      'closing_snapshot_json': jsonDecode(closing.closingSnapshotJson.value),
      'closed_at': closing.closedAt.value.toIso8601String(),
      'reopened_at': closing.reopenedAt.present
          ? closing.reopenedAt.value?.toIso8601String()
          : null,
      'note': closing.note.present ? closing.note.value : null,
      'deleted_at': closing.deletedAt.present
          ? closing.deletedAt.value?.toIso8601String()
          : null,
      'client_updated_at': closing.clientUpdatedAt.value.toIso8601String(),
    };
  }
}

class _ReportTotals {
  const _ReportTotals({
    required this.inflow,
    required this.outflow,
    required this.expense,
    required this.transfer,
    required this.serviceCharge,
    required this.netChange,
  });

  final int inflow;
  final int outflow;
  final int expense;
  final int transfer;
  final int serviceCharge;
  final int netChange;
}

class DayClosingException implements Exception {
  const DayClosingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DayAlreadyClosedException extends DayClosingException {
  const DayAlreadyClosedException()
    : super('This day is already closed. Reopen it before closing again.');
}

class DayNotClosedException extends DayClosingException {
  const DayNotClosedException() : super('This day is not closed.');
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
