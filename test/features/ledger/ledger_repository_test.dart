import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/ledger/data/ledger_repository.dart';
import 'package:dukaan_book/features/ledger/domain/ledger_posting_engine.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late LedgerRepository ledgerRepository;
  late AccountsRepository accountsRepository;
  late OnboardingRepository onboardingRepository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    final idGenerator = IdGenerator();
    database = AppDatabase(NativeDatabase.memory());
    ledgerRepository = LedgerRepository(
      database: database,
      idGenerator: idGenerator,
      postingEngine: const LedgerPostingEngine(),
    );
    accountsRepository = AccountsRepository(
      database: database,
      idGenerator: idGenerator,
    );
    onboardingRepository = OnboardingRepository(
      database: database,
      supabase: null,
      idGenerator: idGenerator,
    );
    await onboardingRepository.completeShopSetup(
      user: _testUser,
      shopName: 'Demo Shop',
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('posts cash in and cash out entries to local balances', () async {
    final cash = await _accountByName(database, 'Cash');

    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.cashIn,
        amount: Money.fromRupees(1000),
        accountId: cash.id,
      ),
    );
    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.cashOut,
        amount: Money.fromRupees(250),
        accountId: cash.id,
      ),
    );

    final balances = await accountsRepository.getAccountBalances(_testUser.id);
    expect(_balanceFor(balances, cash.id), 75000);
  });

  test('posts transfer as one transaction with two lines', () async {
    final cash = await _accountByName(database, 'Cash');
    final bank = await _accountByName(database, 'Bank');

    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.transfer,
        amount: Money.fromRupees(400),
        fromAccountId: cash.id,
        toAccountId: bank.id,
      ),
    );

    final transactions = await database
        .select(database.ledgerTransactions)
        .get();
    final lines = await database.select(database.ledgerLines).get();
    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(transactions, hasLength(1));
    expect(lines, hasLength(2));
    expect(_balanceFor(balances, cash.id), -40000);
    expect(_balanceFor(balances, bank.id), 40000);
  });

  test('blocks same account transfer', () async {
    final cash = await _accountByName(database, 'Cash');

    expect(
      () => ledgerRepository.postEntry(
        userId: _testUser.id,
        write: LedgerEntryWrite(
          kind: LedgerPostingKind.transfer,
          amount: Money.fromRupees(400),
          fromAccountId: cash.id,
          toAccountId: cash.id,
        ),
      ),
      throwsA(isA<LedgerPostingValidationException>()),
    );
  });

  test('posts expense and makes a reusable category bucket', () async {
    final cash = await _accountByName(database, 'Cash');

    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.expense,
        amount: Money.fromRupees(300),
        paymentAccountId: cash.id,
        newExpenseCategoryName: 'Fuel',
      ),
    );
    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.expense,
        amount: Money.fromRupees(200),
        paymentAccountId: cash.id,
        newExpenseCategoryName: 'fuel',
      ),
    );

    final categories = await database.select(database.expenseCategories).get();
    final expenseBuckets = await (database.select(
      database.accounts,
    )..where((row) => row.type.equals('expense_bucket'))).get();
    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(
      categories.where((category) => category.name == 'Fuel'),
      hasLength(1),
    );
    expect(expenseBuckets, hasLength(1));
    expect(_balanceFor(balances, cash.id), -50000);
    expect(_balanceFor(balances, expenseBuckets.single.id), 50000);
  });

  test('unsynced posted transactions can be edited in place', () async {
    final cash = await _accountByName(database, 'Cash');

    await ledgerRepository.postEntry(
      userId: _testUser.id,
      write: LedgerEntryWrite(
        kind: LedgerPostingKind.cashIn,
        amount: Money.fromRupees(100),
        accountId: cash.id,
      ),
    );
    final transaction = await database
        .select(database.ledgerTransactions)
        .getSingle();

    final reversalId = await ledgerRepository.replacePostedTransaction(
      userId: _testUser.id,
      transactionId: transaction.id,
      replacement: LedgerEntryWrite(
        kind: LedgerPostingKind.cashOut,
        amount: Money.fromRupees(25),
        accountId: cash.id,
      ),
    );

    final transactions = await database
        .select(database.ledgerTransactions)
        .get();
    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(reversalId, isNull);
    expect(transactions, hasLength(1));
    expect(transactions.single.kind, 'cash_out');
    expect(_balanceFor(balances, cash.id), -2500);
  });

  test(
    'synced posted transaction edit creates reversal and replacement',
    () async {
      final cash = await _accountByName(database, 'Cash');

      await ledgerRepository.postEntry(
        userId: _testUser.id,
        write: LedgerEntryWrite(
          kind: LedgerPostingKind.cashIn,
          amount: Money.fromRupees(100),
          accountId: cash.id,
        ),
      );
      final transaction = await database
          .select(database.ledgerTransactions)
          .getSingle();
      await (database.update(database.syncOutbox)..where(
            (row) =>
                row.targetTableName.equals('ledger_transactions') &
                row.recordId.equals(transaction.id),
          ))
          .write(SyncOutboxCompanion(syncedAt: Value(DateTime.now().toUtc())));

      final reversalId = await ledgerRepository.replacePostedTransaction(
        userId: _testUser.id,
        transactionId: transaction.id,
        replacement: LedgerEntryWrite(
          kind: LedgerPostingKind.cashIn,
          amount: Money.fromRupees(40),
          accountId: cash.id,
        ),
        correctionNote: 'Corrected amount',
      );

      final transactions = await database
          .select(database.ledgerTransactions)
          .get();
      final original = await (database.select(
        database.ledgerTransactions,
      )..where((row) => row.id.equals(transaction.id))).getSingle();
      final reversal = await (database.select(
        database.ledgerTransactions,
      )..where((row) => row.id.equals(reversalId!))).getSingle();
      final balances = await accountsRepository.getAccountBalances(
        _testUser.id,
      );

      expect(transactions, hasLength(3));
      expect(original.status, 'reversed');
      expect(reversal.kind, 'reversal');
      expect(reversal.reversedTransactionId, transaction.id);
      expect(_balanceFor(balances, cash.id), 4000);
    },
  );

  test('weekly summary uses real data and zero-fills missing days', () async {
    final cash = await _accountByName(database, 'Cash');
    final shop = await (database.select(database.shops)).getSingle();
    final endDate = DateTime(2026, 4, 13);

    await _seedTransaction(
      database: database,
      id: 'week-1',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_in',
      businessDate: DateTime(2026, 4, 7),
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: 10000)],
    );
    await _seedTransaction(
      database: database,
      id: 'week-2',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_out',
      businessDate: DateTime(2026, 4, 10),
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: -2500)],
    );
    await _seedTransaction(
      database: database,
      id: 'week-3',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_in',
      businessDate: endDate,
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: 5000)],
    );

    final points = await ledgerRepository
        .watchWeeklySummary(_testUser.id, endDate: endDate, days: 7)
        .first;

    expect(points, hasLength(7));
    expect(points.first.businessDate, DateTime(2026, 4, 7));
    expect(points[0].netPaisa, 10000);
    expect(points[1].netPaisa, 0);
    expect(points[3].netPaisa, -2500);
    expect(points.last.netPaisa, 5000);
  });

  test('monthly expense summary aggregates expense buckets by month', () async {
    final cash = await _accountByName(database, 'Cash');
    final shop = await (database.select(database.shops)).getSingle();
    final now = DateTime.utc(2026, 4, 13, 9);
    const rentExpenseId = 'expense-rent-test';

    await database.into(database.accounts).insert(
      AccountsCompanion.insert(
        id: rentExpenseId,
        userId: _testUser.id,
        shopId: shop.id,
        name: 'Expense: Rent Test',
        type: 'expense_bucket',
        colorHex: const Value('#D86F45'),
        sortOrder: const Value(99),
        isActive: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
        clientUpdatedAt: now,
      ),
    );

    await _seedTransaction(
      database: database,
      id: 'month-jan-expense',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'expense',
      businessDate: DateTime(2026, 1, 9),
      lines: [
        _SeedLedgerLine(accountId: cash.id, amountPaisa: -12000),
        const _SeedLedgerLine(accountId: rentExpenseId, amountPaisa: 12000),
      ],
    );
    await _seedTransaction(
      database: database,
      id: 'month-mar-expense',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'expense',
      businessDate: DateTime(2026, 3, 5),
      lines: [
        _SeedLedgerLine(accountId: cash.id, amountPaisa: -4000),
        const _SeedLedgerLine(accountId: rentExpenseId, amountPaisa: 4000),
      ],
    );
    await _seedTransaction(
      database: database,
      id: 'month-apr-expense',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'expense',
      businessDate: DateTime(2026, 4, 8),
      lines: [
        _SeedLedgerLine(accountId: cash.id, amountPaisa: -6000),
        const _SeedLedgerLine(accountId: rentExpenseId, amountPaisa: 6000),
      ],
    );

    final points = await ledgerRepository
        .watchMonthlyExpenseSummary(
          _testUser.id,
          endDate: DateTime(2026, 4, 13),
          months: 6,
        )
        .first;

    expect(points, hasLength(6));
    expect(points.first.monthStart, DateTime(2025, 11));
    expect(points[2].monthStart, DateTime(2026, 1));
    expect(points[2].expensePaisa, 12000);
    expect(points[4].monthStart, DateTime(2026, 3));
    expect(points[4].expensePaisa, 4000);
    expect(points.last.monthStart, DateTime(2026, 4));
    expect(points.last.expensePaisa, 6000);
  });

  test('balance trend builds running total for selected date range', () async {
    final cash = await _accountByName(database, 'Cash');
    final shop = await (database.select(database.shops)).getSingle();
    final endDate = DateTime(2026, 4, 13);

    await _seedTransaction(
      database: database,
      id: 'trend-opening',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_in',
      businessDate: DateTime(2026, 4, 8),
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: 50000)],
    );
    await _seedTransaction(
      database: database,
      id: 'trend-plus',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_in',
      businessDate: DateTime(2026, 4, 10),
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: 10000)],
    );
    await _seedTransaction(
      database: database,
      id: 'trend-minus',
      userId: _testUser.id,
      shopId: shop.id,
      kind: 'cash_out',
      businessDate: DateTime(2026, 4, 12),
      lines: [_SeedLedgerLine(accountId: cash.id, amountPaisa: -4000)],
    );

    final points = await ledgerRepository
        .watchBalanceTrend(_testUser.id, endDate: endDate, days: 5)
        .first;

    expect(points, hasLength(5));
    expect(points.first.businessDate, DateTime(2026, 4, 9));
    expect(points[0].totalBalancePaisa, 50000);
    expect(points[1].totalBalancePaisa, 60000);
    expect(points[2].totalBalancePaisa, 60000);
    expect(points[3].totalBalancePaisa, 56000);
    expect(points[4].totalBalancePaisa, 56000);
  });
}

class _SeedLedgerLine {
  const _SeedLedgerLine({required this.accountId, required this.amountPaisa});

  final String accountId;
  final int amountPaisa;
}

Future<void> _seedTransaction({
  required AppDatabase database,
  required String id,
  required String userId,
  required String shopId,
  required String kind,
  required DateTime businessDate,
  required List<_SeedLedgerLine> lines,
}) async {
  final now = DateTime.utc(
    businessDate.year,
    businessDate.month,
    businessDate.day,
    9,
  );

  await database.into(database.ledgerTransactions).insert(
    LedgerTransactionsCompanion.insert(
      id: id,
      userId: userId,
      shopId: shopId,
      kind: kind,
      businessDate: DateTime(
        businessDate.year,
        businessDate.month,
        businessDate.day,
      ),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    ),
  );

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    await database.into(database.ledgerLines).insert(
      LedgerLinesCompanion.insert(
        id: '$id-line-$index',
        userId: userId,
        shopId: shopId,
        transactionId: id,
        accountId: line.accountId,
        amountPaisa: line.amountPaisa,
        createdAt: now,
        updatedAt: now,
        clientUpdatedAt: now,
      ),
    );
  }
}

Future<Account> _accountByName(AppDatabase database, String name) {
  return (database.select(
    database.accounts,
  )..where((row) => row.name.equals(name))).getSingle();
}

int _balanceFor(List<AccountBalance> balances, String accountId) {
  return balances
      .singleWhere((balance) => balance.account.id == accountId)
      .balancePaisa;
}

const _testUser = User(
  id: 'user-1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  email: 'owner@example.com',
  createdAt: '2026-04-13T00:00:00Z',
);
