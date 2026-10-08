import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/features/reports/data/daily_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DailyReportRepository repository;

  const userId = 'user-1';
  const shopId = 'shop-1';
  const cashId = 'account-cash';
  const bankId = 'account-bank';
  const ownerEquityId = 'account-owner-equity';
  const expenseRentId = 'account-expense-rent';
  const expenseSuppliesId = 'account-expense-supplies';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DailyReportRepository(database: database);

    final now = DateTime.utc(2026, 4, 13, 9);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(id: userId, createdAt: now, updatedAt: now),
        );
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(
            id: shopId,
            userId: userId,
            name: 'Demo Shop',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await _insertAccount(
      database: database,
      id: cashId,
      userId: userId,
      shopId: shopId,
      name: 'Cash',
      type: 'cash',
      sortOrder: 0,
      now: now,
    );
    await _insertAccount(
      database: database,
      id: bankId,
      userId: userId,
      shopId: shopId,
      name: 'Bank',
      type: 'bank',
      sortOrder: 1,
      now: now,
    );
    await _insertAccount(
      database: database,
      id: ownerEquityId,
      userId: userId,
      shopId: shopId,
      name: 'Owner Equity',
      type: 'owner_equity',
      sortOrder: 2,
      now: now,
    );
    await _insertAccount(
      database: database,
      id: expenseRentId,
      userId: userId,
      shopId: shopId,
      name: 'Expense: Rent',
      type: 'expense_bucket',
      sortOrder: 3,
      now: now,
      isActive: false,
    );
    await _insertAccount(
      database: database,
      id: expenseSuppliesId,
      userId: userId,
      shopId: shopId,
      name: 'Expense: Supplies',
      type: 'expense_bucket',
      sortOrder: 4,
      now: now,
      isActive: false,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('aggregates balances, movement totals, and grouped expenses', () async {
    final previousDate = DateTime(2026, 4, 12);
    final targetDate = DateTime(2026, 4, 13);
    final nextDate = DateTime(2026, 4, 14);
    final now = DateTime.utc(2026, 4, 13, 9);

    await _insertTransaction(
      database: database,
      id: 'tx-prev-opening',
      userId: userId,
      shopId: shopId,
      kind: 'cash_in',
      businessDate: previousDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: 100000)],
    );

    await _insertTransaction(
      database: database,
      id: 'tx-day-cash-in',
      userId: userId,
      shopId: shopId,
      kind: 'cash_in',
      businessDate: targetDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: 50000)],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-cash-out',
      userId: userId,
      shopId: shopId,
      kind: 'cash_out',
      businessDate: targetDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: -20000)],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-expense-rent-cash',
      userId: userId,
      shopId: shopId,
      kind: 'expense',
      businessDate: targetDate,
      createdAt: now,
      lines: const [
        _SeedLine(accountId: cashId, amountPaisa: -12000),
        _SeedLine(accountId: expenseRentId, amountPaisa: 12000),
      ],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-expense-rent-bank',
      userId: userId,
      shopId: shopId,
      kind: 'expense',
      businessDate: targetDate,
      createdAt: now,
      lines: const [
        _SeedLine(accountId: bankId, amountPaisa: -3000),
        _SeedLine(accountId: expenseRentId, amountPaisa: 3000),
      ],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-expense-supplies',
      userId: userId,
      shopId: shopId,
      kind: 'expense',
      businessDate: targetDate,
      createdAt: now,
      lines: const [
        _SeedLine(accountId: cashId, amountPaisa: -8000),
        _SeedLine(accountId: expenseSuppliesId, amountPaisa: 8000),
      ],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-transfer',
      userId: userId,
      shopId: shopId,
      kind: 'transfer',
      businessDate: targetDate,
      createdAt: now,
      lines: const [
        _SeedLine(accountId: cashId, amountPaisa: -15000),
        _SeedLine(accountId: bankId, amountPaisa: 16000),
      ],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-adjustment-plus',
      userId: userId,
      shopId: shopId,
      kind: 'adjustment',
      businessDate: targetDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: bankId, amountPaisa: 5000)],
    );
    await _insertTransaction(
      database: database,
      id: 'tx-day-adjustment-minus',
      userId: userId,
      shopId: shopId,
      kind: 'adjustment',
      businessDate: targetDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: -2000)],
    );

    await _insertTransaction(
      database: database,
      id: 'tx-next-day',
      userId: userId,
      shopId: shopId,
      kind: 'cash_in',
      businessDate: nextDate,
      createdAt: now,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: 99900)],
    );

    final report = await repository.getDailyReport(
      userId: userId,
      businessDate: targetDate,
    );

    expect(report.inflowPaisa, 55000);
    expect(report.outflowPaisa, 22000);
    expect(report.expensePaisa, 23000);
    expect(report.transferPaisa, 15000);
    expect(report.serviceChargePaisa, 1000);
    expect(report.netChangePaisa, 11000);
    expect(report.hasUnsyncedEntries, isFalse);

    final cashBalance = report.accounts.singleWhere(
      (item) => item.accountId == cashId,
    );
    final bankBalance = report.accounts.singleWhere(
      (item) => item.accountId == bankId,
    );
    expect(cashBalance.openingBalancePaisa, 100000);
    expect(cashBalance.closingBalancePaisa, 93000);
    expect(bankBalance.openingBalancePaisa, 0);
    expect(bankBalance.closingBalancePaisa, 18000);

    expect(report.expensesByCategory, hasLength(2));
    expect(report.expensesByCategory.first.categoryName, 'Rent');
    expect(report.expensesByCategory.first.amountPaisa, 15000);
    expect(report.expensesByCategory.last.categoryName, 'Supplies');
    expect(report.expensesByCategory.last.amountPaisa, 8000);
    expect(report.transactions, hasLength(8));
    expect(
      report.transactions
          .singleWhere((transaction) => transaction.id == 'tx-day-transfer')
          .amountPaisa,
      1000,
    );

    final drillDown = await repository.getTransactionLines(
      transactionId: 'tx-day-expense-rent-cash',
    );
    expect(drillDown, hasLength(2));
    expect(drillDown.any((line) => line.accountId == cashId), isTrue);
    expect(drillDown.any((line) => line.accountId == expenseRentId), isTrue);
  });

  test('filters by business_date and flags unsynced records', () async {
    final targetDate = DateTime(2026, 4, 13);
    final nextDate = DateTime(2026, 4, 14);
    final createdAt = DateTime.utc(2026, 4, 13, 11);

    await _insertTransaction(
      database: database,
      id: 'tx-next-day-created-today',
      userId: userId,
      shopId: shopId,
      kind: 'cash_in',
      businessDate: nextDate,
      createdAt: createdAt,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: 70000)],
    );
    await database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: 'outbox-pending-1',
            targetTableName: 'ledger_transactions',
            recordId: 'tx-next-day-created-today',
            operation: 'upsert',
            payloadJson: '{}',
            createdAt: createdAt,
          ),
        );

    final todayReport = await repository.getDailyReport(
      userId: userId,
      businessDate: targetDate,
    );
    final nextDayReport = await repository.getDailyReport(
      userId: userId,
      businessDate: nextDate,
    );

    expect(todayReport.inflowPaisa, 0);
    expect(todayReport.netChangePaisa, 0);
    expect(todayReport.hasUnsyncedEntries, isTrue);
    expect(todayReport.transactions, isEmpty);

    expect(nextDayReport.inflowPaisa, 70000);
    expect(nextDayReport.netChangePaisa, 70000);
    expect(nextDayReport.transactions, hasLength(1));
    expect(nextDayReport.transactions.single.id, 'tx-next-day-created-today');
  });

  test('close day saves snapshot and prevents duplicate close', () async {
    final targetDate = DateTime(2026, 4, 13);
    final createdAt = DateTime.utc(2026, 4, 13, 12);

    await _insertTransaction(
      database: database,
      id: 'tx-close-cash-in',
      userId: userId,
      shopId: shopId,
      kind: 'cash_in',
      businessDate: targetDate,
      createdAt: createdAt,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: 45000)],
    );

    await repository.closeDay(userId: userId, businessDate: targetDate);

    final closings = await database.select(database.dailyClosings).get();
    final outbox = await database.select(database.syncOutbox).get();
    expect(closings, hasLength(1));
    expect(closings.single.reopenedAt, isNull);
    expect(closings.single.totalInPaisa, 45000);
    expect(outbox.single.targetTableName, 'daily_closings');
    expect(outbox.single.recordId, closings.single.id);

    final report = await repository.getDailyReport(
      userId: userId,
      businessDate: targetDate,
    );
    expect(report.isClosed, isTrue);
    expect(report.transactions, hasLength(1));
    expect(report.transactions.single.id, 'tx-close-cash-in');

    expect(
      () => repository.closeDay(userId: userId, businessDate: targetDate),
      throwsA(isA<DayAlreadyClosedException>()),
    );
  });

  test('reopen is explicit and closed snapshot remains stable', () async {
    final targetDate = DateTime(2026, 4, 13);
    final createdAt = DateTime.utc(2026, 4, 13, 13);

    await _insertTransaction(
      database: database,
      id: 'tx-reopen-cash-out',
      userId: userId,
      shopId: shopId,
      kind: 'cash_out',
      businessDate: targetDate,
      createdAt: createdAt,
      lines: const [_SeedLine(accountId: cashId, amountPaisa: -9000)],
    );
    await repository.closeDay(userId: userId, businessDate: targetDate);

    await (database.update(
      database.accounts,
    )..where((row) => row.id.equals(cashId))).write(
      AccountsCompanion(
        name: const Value('Cash Renamed'),
        updatedAt: Value(createdAt),
        clientUpdatedAt: Value(createdAt),
      ),
    );

    final closedReport = await repository.getDailyReport(
      userId: userId,
      businessDate: targetDate,
    );
    expect(closedReport.isClosed, isTrue);
    final closedCash = closedReport.accounts.singleWhere(
      (item) => item.accountId == cashId,
    );
    expect(closedCash.accountName, 'Cash');

    await repository.reopenDay(userId: userId, businessDate: targetDate);

    final reopenedReport = await repository.getDailyReport(
      userId: userId,
      businessDate: targetDate,
    );
    expect(reopenedReport.isClosed, isFalse);
    final reopenedCash = reopenedReport.accounts.singleWhere(
      (item) => item.accountId == cashId,
    );
    expect(reopenedCash.accountName, 'Cash Renamed');

    final closings = await database.select(database.dailyClosings).get();
    final outbox = await database.select(database.syncOutbox).get();
    expect(closings.single.reopenedAt, isNotNull);
    expect(
      outbox.where((item) => item.targetTableName == 'daily_closings'),
      hasLength(2),
    );

    expect(
      () => repository.reopenDay(userId: userId, businessDate: targetDate),
      throwsA(isA<DayNotClosedException>()),
    );
  });
}

Future<void> _insertAccount({
  required AppDatabase database,
  required String id,
  required String userId,
  required String shopId,
  required String name,
  required String type,
  required int sortOrder,
  required DateTime now,
  bool isActive = true,
}) {
  return database
      .into(database.accounts)
      .insert(
        AccountsCompanion.insert(
          id: id,
          userId: userId,
          shopId: shopId,
          name: name,
          type: type,
          sortOrder: Value(sortOrder),
          isActive: Value(isActive),
          createdAt: now,
          updatedAt: now,
          clientUpdatedAt: now,
        ),
      );
}

Future<void> _insertTransaction({
  required AppDatabase database,
  required String id,
  required String userId,
  required String shopId,
  required String kind,
  required DateTime businessDate,
  required DateTime createdAt,
  required List<_SeedLine> lines,
}) async {
  await database
      .into(database.ledgerTransactions)
      .insert(
        LedgerTransactionsCompanion.insert(
          id: id,
          userId: userId,
          shopId: shopId,
          kind: kind,
          businessDate: businessDate,
          createdAt: createdAt,
          updatedAt: createdAt,
          clientUpdatedAt: createdAt,
        ),
      );

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    await database
        .into(database.ledgerLines)
        .insert(
          LedgerLinesCompanion.insert(
            id: '$id-line-$index',
            userId: userId,
            shopId: shopId,
            transactionId: id,
            accountId: line.accountId,
            amountPaisa: line.amountPaisa,
            createdAt: createdAt,
            updatedAt: createdAt,
            clientUpdatedAt: createdAt,
          ),
        );
  }
}

class _SeedLine {
  const _SeedLine({required this.accountId, required this.amountPaisa});

  final String accountId;
  final int amountPaisa;
}
