import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/core/time/business_date.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/ledger/domain/ledger_posting_engine.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LedgerRepository(
    database: ref.watch(appDatabaseProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    postingEngine: const LedgerPostingEngine(),
  );
});

final expenseCategoriesProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(ledgerRepositoryProvider).watchExpenseCategories(userId);
    });

final latestActivityProvider =
    StreamProvider.autoDispose<List<LedgerActivityItem>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(ledgerRepositoryProvider).watchLatestActivity(userId);
    });

final todayNetChangeProvider = StreamProvider.autoDispose<int>((ref) {
  final userId = ref.watch(_currentUserIdForLedgerProvider);
  if (userId == null) {
    return Stream.value(0);
  }
  return ref.watch(ledgerRepositoryProvider).watchTodayNetChange(userId);
});

final todayExpensesProvider =
    StreamProvider.autoDispose<List<TodayExpenseItem>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(ledgerRepositoryProvider).watchTodayExpenses(userId);
    });

final weeklySummaryProvider =
    StreamProvider.autoDispose<List<WeeklySummaryPoint>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(ledgerRepositoryProvider).watchWeeklySummary(userId);
    });

final monthlyExpenseSummaryProvider =
    StreamProvider.autoDispose<List<MonthlyExpensePoint>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref
          .watch(ledgerRepositoryProvider)
          .watchMonthlyExpenseSummary(userId);
    });

final balanceTrendProvider =
    StreamProvider.autoDispose<List<BalanceTrendPoint>>((ref) {
      final userId = ref.watch(_currentUserIdForLedgerProvider);
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(ledgerRepositoryProvider).watchBalanceTrend(userId);
    });

final _currentUserIdForLedgerProvider = Provider<String?>((ref) {
  return ref.watch(authRepositoryProvider).currentUser?.id;
});

class LedgerEntryWrite {
  const LedgerEntryWrite({
    required this.kind,
    required this.amount,
    this.serviceCharge,
    this.accountId,
    this.fromAccountId,
    this.toAccountId,
    this.paymentAccountId,
    this.expenseCategoryId,
    this.newExpenseCategoryName,
    this.note,
    this.externalRef,
  });

  final LedgerPostingKind kind;
  final Money amount;
  final Money? serviceCharge;
  final String? accountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String? paymentAccountId;
  final String? expenseCategoryId;
  final String? newExpenseCategoryName;
  final String? note;
  final String? externalRef;
}

class LedgerActivityItem {
  const LedgerActivityItem({
    required this.id,
    required this.kind,
    required this.businessDate,
    required this.createdAt,
    required this.amountPaisa,
    this.note,
    this.primaryAccountName,
  });

  final String id;
  final String kind;
  final DateTime businessDate;
  final DateTime createdAt;
  final int amountPaisa;
  final String? note;
  final String? primaryAccountName;

  Money get amount => Money.fromPaisa(amountPaisa);
}

class TodayExpenseItem {
  const TodayExpenseItem({
    required this.transactionId,
    required this.categoryName,
    required this.paymentAccountName,
    required this.amountPaisa,
    this.note,
  });

  final String transactionId;
  final String categoryName;
  final String paymentAccountName;
  final int amountPaisa;
  final String? note;

  Money get amount => Money.fromPaisa(amountPaisa);
}

class WeeklySummaryPoint {
  const WeeklySummaryPoint({
    required this.businessDate,
    required this.netPaisa,
  });

  final DateTime businessDate;
  final int netPaisa;
}

class MonthlyExpensePoint {
  const MonthlyExpensePoint({
    required this.monthStart,
    required this.expensePaisa,
  });

  final DateTime monthStart;
  final int expensePaisa;
}

class BalanceTrendPoint {
  const BalanceTrendPoint({
    required this.businessDate,
    required this.totalBalancePaisa,
  });

  final DateTime businessDate;
  final int totalBalancePaisa;
}

class LedgerRepository {
  const LedgerRepository({
    required this.database,
    required this.idGenerator,
    required this.postingEngine,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final LedgerPostingEngine postingEngine;

  Stream<List<ExpenseCategory>> watchExpenseCategories(String userId) {
    return database
        .customSelect(
          '''
          SELECT c.*
          FROM expense_categories AS c
          WHERE c.shop_id = (${_activeShopSql(userId)})
            AND c.deleted_at IS NULL
          ORDER BY c.sort_order ASC, c.name COLLATE NOCASE ASC
          ''',
          readsFrom: {
            database.expenseCategories,
            database.shops,
            database.shopMembers,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => database.expenseCategories.map(row.data))
              .toList(growable: false),
        );
  }

  Stream<List<LedgerActivityItem>> watchLatestActivity(
    String userId, {
    int limit = 8,
  }) {
    return database
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
            (
              SELECT a2.name
              FROM ledger_lines AS l2
              INNER JOIN accounts AS a2 ON a2.id = l2.account_id
              WHERE l2.transaction_id = t.id
                AND a2.type != 'expense_bucket'
              ORDER BY ABS(l2.amount_paisa) DESC
              LIMIT 1
            ) AS primary_account_name
          FROM ledger_transactions AS t
          INNER JOIN ledger_lines AS l ON l.transaction_id = t.id
          WHERE t.shop_id = (${_activeShopSql(userId)})
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
          GROUP BY t.id
          ORDER BY t.created_at DESC
          LIMIT ?
          ''',
          variables: [Variable<int>(limit)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => LedgerActivityItem(
                  id: row.read<String>('id'),
                  kind: row.read<String>('kind'),
                  businessDate: row.read<DateTime>('business_date'),
                  createdAt: row.read<DateTime>('created_at'),
                  note: row.readNullable<String>('note'),
                  amountPaisa: row.read<int>('display_amount_paisa'),
                  primaryAccountName: row.readNullable<String>(
                    'primary_account_name',
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<int> watchTodayNetChange(String userId) {
    final today = BusinessDate.today();
    return database
        .customSelect(
          '''
          SELECT COALESCE(SUM(l.amount_paisa), 0) AS total_paisa
          FROM ledger_lines AS l
          INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
          INNER JOIN accounts AS a ON a.id = l.account_id
          WHERE t.shop_id = (${_activeShopSql(userId)})
            AND t.business_date = ?
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
            AND a.type NOT IN ('owner_equity', 'expense_bucket')
          ''',
          variables: [Variable<DateTime>(today)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .watchSingle()
        .map((row) => row.read<int>('total_paisa'));
  }

  Stream<List<TodayExpenseItem>> watchTodayExpenses(String userId) {
    final today = BusinessDate.today();
    return database
        .customSelect(
          '''
          SELECT
            t.id AS transaction_id,
            REPLACE(expense_account.name, 'Expense: ', '') AS category_name,
            payment_account.name AS payment_account_name,
            ABS(payment_line.amount_paisa) AS amount_paisa,
            t.note
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
            AND expense_account.type = 'expense_bucket'
          ORDER BY t.created_at DESC
          ''',
          variables: [Variable<DateTime>(today)],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => TodayExpenseItem(
                  transactionId: row.read<String>('transaction_id'),
                  categoryName: row.read<String>('category_name'),
                  paymentAccountName: row.read<String>('payment_account_name'),
                  amountPaisa: row.read<int>('amount_paisa'),
                  note: row.readNullable<String>('note'),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<List<WeeklySummaryPoint>> watchWeeklySummary(
    String userId, {
    DateTime? endDate,
    int days = 7,
  }) {
    final normalizedEnd = _normalizeDate(endDate ?? BusinessDate.today());
    final normalizedStart = normalizedEnd.subtract(Duration(days: days - 1));
    final daysRange = List<DateTime>.generate(
      days,
      (index) => normalizedStart.add(Duration(days: index)),
      growable: false,
    );

    return database
        .customSelect(
          '''
          SELECT
            t.business_date,
            COALESCE(SUM(l.amount_paisa), 0) AS net_paisa
          FROM ledger_transactions AS t
          INNER JOIN ledger_lines AS l ON l.transaction_id = t.id
          INNER JOIN accounts AS a ON a.id = l.account_id
          WHERE t.shop_id = (${_activeShopSql(userId)})
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
            AND a.type NOT IN ('owner_equity', 'expense_bucket')
            AND t.business_date BETWEEN ? AND ?
          GROUP BY t.business_date
          ORDER BY t.business_date ASC
          ''',
          variables: [
            Variable<DateTime>(normalizedStart),
            Variable<DateTime>(normalizedEnd),
          ],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .watch()
        .map((rows) {
          final netByDate = <String, int>{
            for (final row in rows)
              _dateKey(_normalizeDate(row.read<DateTime>('business_date'))): row
                  .read<int>('net_paisa'),
          };

          return daysRange
              .map(
                (day) => WeeklySummaryPoint(
                  businessDate: day,
                  netPaisa: netByDate[_dateKey(day)] ?? 0,
                ),
              )
              .toList(growable: false);
        });
  }

  Stream<List<MonthlyExpensePoint>> watchMonthlyExpenseSummary(
    String userId, {
    DateTime? endDate,
    int months = 6,
  }) {
    final normalizedEnd = _normalizeDate(endDate ?? BusinessDate.today());
    final endMonth = DateTime(normalizedEnd.year, normalizedEnd.month);
    final startMonth = DateTime(endMonth.year, endMonth.month - (months - 1));
    final endMonthLastDay = DateTime(endMonth.year, endMonth.month + 1, 0);
    final monthRange = List<DateTime>.generate(
      months,
      (index) => DateTime(startMonth.year, startMonth.month + index),
      growable: false,
    );

    return database
        .customSelect(
          '''
          SELECT
            t.business_date,
            COALESCE(SUM(l.amount_paisa), 0) AS expense_paisa
          FROM ledger_transactions AS t
          INNER JOIN ledger_lines AS l ON l.transaction_id = t.id
          INNER JOIN accounts AS a ON a.id = l.account_id
          WHERE t.shop_id = (${_activeShopSql(userId)})
            AND t.kind = 'expense'
            AND t.deleted_at IS NULL
            AND l.deleted_at IS NULL
            AND a.type = 'expense_bucket'
            AND l.amount_paisa > 0
            AND t.business_date BETWEEN ? AND ?
          GROUP BY t.business_date
          ORDER BY t.business_date ASC
          ''',
          variables: [
            Variable<DateTime>(startMonth),
            Variable<DateTime>(endMonthLastDay),
          ],
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.accounts,
            database.shops,
          },
        )
        .watch()
        .map((rows) {
          final monthTotals = <String, int>{};
          for (final row in rows) {
            final date = _normalizeDate(row.read<DateTime>('business_date'));
            final key = _monthKey(date);
            monthTotals[key] =
                (monthTotals[key] ?? 0) + row.read<int>('expense_paisa');
          }

          return monthRange
              .map(
                (monthStart) => MonthlyExpensePoint(
                  monthStart: monthStart,
                  expensePaisa: monthTotals[_monthKey(monthStart)] ?? 0,
                ),
              )
              .toList(growable: false);
        });
  }

  Stream<List<BalanceTrendPoint>> watchBalanceTrend(
    String userId, {
    DateTime? endDate,
    int days = 14,
  }) {
    final normalizedEnd = _normalizeDate(endDate ?? BusinessDate.today());
    final normalizedStart = normalizedEnd.subtract(Duration(days: days - 1));
    final daysRange = List<DateTime>.generate(
      days,
      (index) => normalizedStart.add(Duration(days: index)),
      growable: false,
    );

    return database
        .customSelect(
          '''
          SELECT
            (SELECT COUNT(*) FROM ledger_transactions WHERE shop_id = (${_activeShopSql(userId)})) AS tx_count,
            (SELECT COUNT(*) FROM ledger_lines WHERE shop_id = (${_activeShopSql(userId)})) AS line_count
          ''',
          readsFrom: {
            database.ledgerTransactions,
            database.ledgerLines,
            database.shops,
          },
        )
        .watchSingle()
        .asyncMap((_) async {
          final openingRow = await database
              .customSelect(
                '''
            SELECT COALESCE(SUM(l.amount_paisa), 0) AS opening_paisa
            FROM ledger_lines AS l
            INNER JOIN ledger_transactions AS t ON t.id = l.transaction_id
            INNER JOIN accounts AS a ON a.id = l.account_id
            WHERE t.shop_id = (${_activeShopSql(userId)})
              AND t.deleted_at IS NULL
              AND l.deleted_at IS NULL
              AND a.type NOT IN ('owner_equity', 'expense_bucket')
              AND t.business_date < ?
            ''',
                variables: [Variable<DateTime>(normalizedStart)],
                readsFrom: {
                  database.ledgerTransactions,
                  database.ledgerLines,
                  database.accounts,
                  database.shops,
                },
              )
              .getSingle();
          final openingBalance = openingRow.read<int>('opening_paisa');

          final rows = await database
              .customSelect(
                '''
            SELECT
              t.business_date,
              COALESCE(SUM(l.amount_paisa), 0) AS net_paisa
            FROM ledger_transactions AS t
            INNER JOIN ledger_lines AS l ON l.transaction_id = t.id
            INNER JOIN accounts AS a ON a.id = l.account_id
            WHERE t.shop_id = (${_activeShopSql(userId)})
              AND t.deleted_at IS NULL
              AND l.deleted_at IS NULL
              AND a.type NOT IN ('owner_equity', 'expense_bucket')
              AND t.business_date BETWEEN ? AND ?
            GROUP BY t.business_date
            ORDER BY t.business_date ASC
            ''',
                variables: [
                  Variable<DateTime>(normalizedStart),
                  Variable<DateTime>(normalizedEnd),
                ],
                readsFrom: {
                  database.ledgerTransactions,
                  database.ledgerLines,
                  database.accounts,
                  database.shops,
                },
              )
              .get();

          final netByDate = <String, int>{
            for (final row in rows)
              _dateKey(_normalizeDate(row.read<DateTime>('business_date'))): row
                  .read<int>('net_paisa'),
          };

          var runningBalance = openingBalance;
          return daysRange
              .map((day) {
                runningBalance += netByDate[_dateKey(day)] ?? 0;
                return BalanceTrendPoint(
                  businessDate: day,
                  totalBalancePaisa: runningBalance,
                );
              })
              .toList(growable: false);
        });
  }

  Future<bool> canEditPostedTransactionDirectly(String transactionId) async {
    final pending =
        await (database.select(database.syncOutbox)..where(
              (row) =>
                  row.targetTableName.equals('ledger_transactions') &
                  row.recordId.equals(transactionId) &
                  row.syncedAt.isNull(),
            ))
            .getSingleOrNull();
    return pending != null;
  }

  Future<String?> replacePostedTransaction({
    required String userId,
    required String transactionId,
    required LedgerEntryWrite replacement,
    String? correctionNote,
  }) async {
    final original = await _requireTransaction(transactionId);
    if (original.status != 'posted') {
      throw StateError('Only posted transactions can be corrected.');
    }

    final canEditDirectly = await canEditPostedTransactionDirectly(
      transactionId,
    );
    if (canEditDirectly) {
      await _replaceUnsyncedTransaction(
        userId: userId,
        original: original,
        replacement: replacement,
      );
      return null;
    }

    final reversalId = await _reverseSyncedTransaction(
      original: original,
      note: correctionNote,
    );
    await postEntry(userId: userId, write: replacement);
    return reversalId;
  }

  Future<void> postEntry({
    required String userId,
    required LedgerEntryWrite write,
  }) async {
    final shop = await _requireShop(userId);
    final now = DateTime.now().toUtc();
    final businessDate = BusinessDate.today(now);
    final expenseAccountId = write.kind == LedgerPostingKind.expense
        ? await _requireExpenseBucketAccount(
            userId: userId,
            shopId: shop.id,
            categoryId: await _resolveExpenseCategoryId(
              userId: userId,
              shopId: shop.id,
              write: write,
              now: now,
            ),
            now: now,
          )
        : null;
    final lines = postingEngine.buildLines(
      LedgerPostingDraft(
        kind: write.kind,
        amountPaisa: write.amount.paisa,
        serviceChargePaisa: write.serviceCharge?.paisa ?? 0,
        accountId: write.accountId,
        fromAccountId: write.fromAccountId,
        toAccountId: write.toAccountId,
        paymentAccountId: write.paymentAccountId,
        expenseAccountId: expenseAccountId,
      ),
    );
    final transactionId = idGenerator.next();

    await database.transaction(() async {
      final transaction = LedgerTransactionsCompanion.insert(
        id: transactionId,
        userId: userId,
        shopId: shop.id,
        kind: write.kind.value,
        businessDate: businessDate,
        note: Value(_nullableTrim(write.note)),
        externalRef: Value(_nullableTrim(write.externalRef)),
        createdAt: now,
        updatedAt: now,
        clientUpdatedAt: now,
      );
      await database.into(database.ledgerTransactions).insert(transaction);
      await _queueOutbox(
        targetTableName: 'ledger_transactions',
        recordId: transactionId,
        operation: 'upsert',
        payload: _transactionPayload(transaction),
        now: now,
      );

      for (final line in lines) {
        final companion = LedgerLinesCompanion.insert(
          id: idGenerator.next(),
          userId: userId,
          shopId: shop.id,
          transactionId: transactionId,
          accountId: line.accountId,
          amountPaisa: line.amountPaisa,
          memo: Value(line.memo),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        );
        await database.into(database.ledgerLines).insert(companion);
        await _queueOutbox(
          targetTableName: 'ledger_lines',
          recordId: companion.id.value,
          operation: 'upsert',
          payload: _linePayload(companion),
          now: now,
        );
      }
    });
  }

  Future<LedgerTransaction> _requireTransaction(String transactionId) async {
    final transaction =
        await (database.select(database.ledgerTransactions)
              ..where((row) => row.id.equals(transactionId))
              ..where((row) => row.deletedAt.isNull()))
            .getSingleOrNull();
    if (transaction == null) {
      throw StateError('Transaction not found.');
    }
    return transaction;
  }

  Future<void> _replaceUnsyncedTransaction({
    required String userId,
    required LedgerTransaction original,
    required LedgerEntryWrite replacement,
  }) async {
    final now = DateTime.now().toUtc();
    final expenseAccountId = replacement.kind == LedgerPostingKind.expense
        ? await _requireExpenseBucketAccount(
            userId: userId,
            shopId: original.shopId,
            categoryId: await _resolveExpenseCategoryId(
              userId: userId,
              shopId: original.shopId,
              write: replacement,
              now: now,
            ),
            now: now,
          )
        : null;
    final lines = postingEngine.buildLines(
      LedgerPostingDraft(
        kind: replacement.kind,
        amountPaisa: replacement.amount.paisa,
        serviceChargePaisa: replacement.serviceCharge?.paisa ?? 0,
        accountId: replacement.accountId,
        fromAccountId: replacement.fromAccountId,
        toAccountId: replacement.toAccountId,
        paymentAccountId: replacement.paymentAccountId,
        expenseAccountId: expenseAccountId,
      ),
    );

    await database.transaction(() async {
      final oldLines = await (database.select(
        database.ledgerLines,
      )..where((row) => row.transactionId.equals(original.id))).get();
      for (final line in oldLines) {
        await (database.delete(database.syncOutbox)..where(
              (row) =>
                  row.targetTableName.equals('ledger_lines') &
                  row.recordId.equals(line.id) &
                  row.syncedAt.isNull(),
            ))
            .go();
      }
      await (database.delete(
        database.ledgerLines,
      )..where((row) => row.transactionId.equals(original.id))).go();
      final transaction = LedgerTransactionsCompanion(
        id: Value(original.id),
        userId: Value(original.userId),
        shopId: Value(original.shopId),
        kind: Value(replacement.kind.value),
        status: const Value('posted'),
        businessDate: Value(original.businessDate),
        note: Value(_nullableTrim(replacement.note)),
        externalRef: Value(_nullableTrim(replacement.externalRef)),
        reversedTransactionId: const Value(null),
        createdAt: Value(original.createdAt),
        updatedAt: Value(now),
        deletedAt: const Value(null),
        clientUpdatedAt: Value(now),
      );
      await database.update(database.ledgerTransactions).replace(transaction);
      await _queueOutbox(
        targetTableName: 'ledger_transactions',
        recordId: original.id,
        operation: 'upsert',
        payload: _transactionPayload(transaction),
        now: now,
      );
      for (final line in lines) {
        final companion = LedgerLinesCompanion.insert(
          id: idGenerator.next(),
          userId: userId,
          shopId: original.shopId,
          transactionId: original.id,
          accountId: line.accountId,
          amountPaisa: line.amountPaisa,
          memo: Value(line.memo),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        );
        await database.into(database.ledgerLines).insert(companion);
        await _queueOutbox(
          targetTableName: 'ledger_lines',
          recordId: companion.id.value,
          operation: 'upsert',
          payload: _linePayload(companion),
          now: now,
        );
      }
    });
  }

  Future<String> _reverseSyncedTransaction({
    required LedgerTransaction original,
    String? note,
  }) async {
    final originalLines =
        await (database.select(database.ledgerLines)
              ..where((row) => row.transactionId.equals(original.id))
              ..where((row) => row.deletedAt.isNull()))
            .get();
    if (originalLines.isEmpty) {
      throw StateError('Transaction has no ledger lines to reverse.');
    }

    final now = DateTime.now().toUtc();
    final reversalId = idGenerator.next();
    await database.transaction(() async {
      final reversedOriginal = LedgerTransactionsCompanion(
        id: Value(original.id),
        userId: Value(original.userId),
        shopId: Value(original.shopId),
        kind: Value(original.kind),
        status: const Value('reversed'),
        businessDate: Value(original.businessDate),
        note: Value(original.note),
        externalRef: Value(original.externalRef),
        reversedTransactionId: Value(original.reversedTransactionId),
        createdAt: Value(original.createdAt),
        updatedAt: Value(now),
        deletedAt: Value(original.deletedAt),
        clientUpdatedAt: Value(now),
      );
      await database
          .update(database.ledgerTransactions)
          .replace(reversedOriginal);
      await _queueOutbox(
        targetTableName: 'ledger_transactions',
        recordId: original.id,
        operation: 'upsert',
        payload: _transactionPayload(reversedOriginal),
        now: now,
      );

      final reversal = LedgerTransactionsCompanion.insert(
        id: reversalId,
        userId: original.userId,
        shopId: original.shopId,
        kind: 'reversal',
        businessDate: original.businessDate,
        note: Value(_nullableTrim(note) ?? 'Correction reversal'),
        reversedTransactionId: Value(original.id),
        createdAt: now,
        updatedAt: now,
        clientUpdatedAt: now,
      );
      await database.into(database.ledgerTransactions).insert(reversal);
      await _queueOutbox(
        targetTableName: 'ledger_transactions',
        recordId: reversalId,
        operation: 'upsert',
        payload: _transactionPayload(reversal),
        now: now,
      );

      for (final originalLine in originalLines) {
        final line = LedgerLinesCompanion.insert(
          id: idGenerator.next(),
          userId: originalLine.userId,
          shopId: originalLine.shopId,
          transactionId: reversalId,
          accountId: originalLine.accountId,
          amountPaisa: -originalLine.amountPaisa,
          memo: const Value('Reversal'),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        );
        await database.into(database.ledgerLines).insert(line);
        await _queueOutbox(
          targetTableName: 'ledger_lines',
          recordId: line.id.value,
          operation: 'upsert',
          payload: _linePayload(line),
          now: now,
        );
      }
    });
    return reversalId;
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
      throw StateError('Create a shop before posting entries.');
    }
    return shop;
  }

  Future<String> _resolveExpenseCategoryId({
    required String userId,
    required String shopId,
    required LedgerEntryWrite write,
    required DateTime now,
  }) async {
    final existingId = _nullableTrim(write.expenseCategoryId);
    if (existingId != null) {
      return existingId;
    }

    final categoryName = _nullableTrim(write.newExpenseCategoryName);
    if (categoryName == null) {
      throw const LedgerPostingValidationException(
        'Expense category is required.',
      );
    }

    final categories =
        await (database.select(database.expenseCategories)
              ..where((row) => row.shopId.equals(shopId))
              ..where((row) => row.deletedAt.isNull()))
            .get();
    final existing = categories
        .where(
          (category) =>
              category.name.toLowerCase() == categoryName.toLowerCase(),
        )
        .firstOrNull;
    if (existing != null) {
      return existing.id;
    }

    final count = await (database.select(
      database.expenseCategories,
    )..where((row) => row.shopId.equals(shopId))).get();
    final category = ExpenseCategoriesCompanion.insert(
      id: idGenerator.next(),
      userId: userId,
      shopId: shopId,
      name: categoryName,
      icon: const Value('sell'),
      sortOrder: Value(count.length),
      isSystem: const Value(false),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    );

    await database.into(database.expenseCategories).insert(category);
    await _queueOutbox(
      targetTableName: 'expense_categories',
      recordId: category.id.value,
      operation: 'upsert',
      payload: _categoryPayload(category),
      now: now,
    );
    return category.id.value;
  }

  Future<String> _requireExpenseBucketAccount({
    required String userId,
    required String shopId,
    required String categoryId,
    required DateTime now,
  }) async {
    final category = await (database.select(
      database.expenseCategories,
    )..where((row) => row.id.equals(categoryId))).getSingleOrNull();
    if (category == null) {
      throw const LedgerPostingValidationException(
        'Expense category was not found.',
      );
    }

    final existing =
        await (database.select(database.accounts)
              ..where((row) => row.shopId.equals(shopId))
              ..where((row) => row.type.equals('expense_bucket'))
              ..where((row) => row.name.equals('Expense: ${category.name}'))
              ..where((row) => row.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }

    final count = await (database.select(
      database.accounts,
    )..where((row) => row.shopId.equals(shopId))).get();
    final account = AccountsCompanion.insert(
      id: idGenerator.next(),
      userId: userId,
      shopId: shopId,
      name: 'Expense: ${category.name}',
      type: 'expense_bucket',
      colorHex: const Value('#D86F45'),
      sortOrder: Value(count.length),
      isActive: const Value(false),
      isSystem: const Value(true),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    );
    await database.into(database.accounts).insert(account);
    await _queueOutbox(
      targetTableName: 'accounts',
      recordId: account.id.value,
      operation: 'upsert',
      payload: _accountPayload(account),
      now: now,
    );
    return account.id.value;
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

  static Map<String, Object?> _transactionPayload(
    LedgerTransactionsCompanion transaction,
  ) {
    return {
      'id': transaction.id.value,
      'user_id': transaction.userId.value,
      'shop_id': transaction.shopId.value,
      'kind': transaction.kind.value,
      'status': transaction.status.present
          ? transaction.status.value
          : 'posted',
      'business_date': transaction.businessDate.value.toIso8601String(),
      'note': transaction.note.value,
      'external_ref': transaction.externalRef.value,
      'client_updated_at': transaction.clientUpdatedAt.value.toIso8601String(),
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

  static Map<String, Object?> _categoryPayload(
    ExpenseCategoriesCompanion category,
  ) {
    return {
      'id': category.id.value,
      'user_id': category.userId.value,
      'shop_id': category.shopId.value,
      'name': category.name.value,
      'icon': category.icon.value,
      'sort_order': category.sortOrder.value,
      'is_system': category.isSystem.value,
      'client_updated_at': category.clientUpdatedAt.value.toIso8601String(),
    };
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
      'low_balance_threshold_paisa': account.lowBalanceThresholdPaisa.present
          ? account.lowBalanceThresholdPaisa.value
          : null,
      'client_updated_at': account.clientUpdatedAt.value.toIso8601String(),
    };
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _monthKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    return '${value.year}-$month';
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
