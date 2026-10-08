import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late AccountsRepository accountsRepository;
  late OnboardingRepository onboardingRepository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    final idGenerator = IdGenerator();
    database = AppDatabase(NativeDatabase.memory());
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

  test('posts opening balances with owner equity offsets', () async {
    final cash = await _accountByName(database, 'Cash');
    final bank = await _accountByName(database, 'Bank');
    final ownerEquity = await _accountByName(database, 'Owner Equity');

    await accountsRepository.postOpeningBalances(
      userId: _testUser.id,
      drafts: [
        OpeningBalanceDraft(accountId: cash.id, amount: Money.fromRupees(1500)),
        OpeningBalanceDraft(accountId: bank.id, amount: Money.fromRupees(2500)),
      ],
    );

    final transactions = await database
        .select(database.ledgerTransactions)
        .get();
    final lines = await database.select(database.ledgerLines).get();
    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(transactions, hasLength(2));
    expect(lines, hasLength(4));
    expect(_balanceFor(balances, cash.id), 150000);
    expect(_balanceFor(balances, bank.id), 250000);
    expect(_balanceFor(balances, ownerEquity.id), -400000);
  });

  test('opening balances post only the delta from current balances', () async {
    final cash = await _accountByName(database, 'Cash');
    final ownerEquity = await _accountByName(database, 'Owner Equity');

    await accountsRepository.postOpeningBalances(
      userId: _testUser.id,
      drafts: [
        OpeningBalanceDraft(accountId: cash.id, amount: Money.fromRupees(1500)),
      ],
    );
    await accountsRepository.postOpeningBalances(
      userId: _testUser.id,
      drafts: [
        OpeningBalanceDraft(accountId: cash.id, amount: Money.fromRupees(1500)),
      ],
    );

    final transactions = await database
        .select(database.ledgerTransactions)
        .get();
    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(transactions, hasLength(1));
    expect(_balanceFor(balances, cash.id), 150000);
    expect(_balanceFor(balances, ownerEquity.id), -150000);
  });

  test('account balances ignore lines from deleted transactions', () async {
    final cash = await _accountByName(database, 'Cash');
    final ownerEquity = await _accountByName(database, 'Owner Equity');

    await accountsRepository.postOpeningBalances(
      userId: _testUser.id,
      drafts: [
        OpeningBalanceDraft(accountId: cash.id, amount: Money.fromRupees(1500)),
      ],
    );
    final transaction = await database
        .select(database.ledgerTransactions)
        .getSingle();
    await (database.update(
      database.ledgerTransactions,
    )..where((row) => row.id.equals(transaction.id))).write(
      LedgerTransactionsCompanion(deletedAt: Value(DateTime.now().toUtc())),
    );

    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(_balanceFor(balances, cash.id), 0);
    expect(_balanceFor(balances, ownerEquity.id), 0);
  });

  test('ignores malformed money before posting opening balances', () {
    expect(() => MoneyParser.parsePkr('12.345'), throwsFormatException);
    expect(() => MoneyParser.parsePkr('abc'), throwsFormatException);
  });

  test('creates edits and deactivates custom account through outbox', () async {
    final account = await accountsRepository.createAccount(
      userId: _testUser.id,
      write: const AccountWrite(
        name: 'Supplier Wallet',
        type: 'wallet',
        colorHex: '#2563EB',
        lowBalanceThreshold: Money.fromPaisa(50000),
      ),
    );

    await accountsRepository.updateAccount(
      accountId: account.id,
      write: const AccountWrite(
        name: 'Supplier Wallet Main',
        type: 'wallet',
        colorHex: '#D86F45',
      ),
    );
    await accountsRepository.deactivateAccount(account.id);

    final updated = await accountsRepository.getAccount(account.id);
    final outbox = await database.select(database.syncOutbox).get();

    expect(updated?.name, 'Supplier Wallet Main');
    expect(updated?.isActive, isFalse);
    expect(updated?.colorHex, '#D86F45');
    expect(
      outbox.where(
        (item) =>
            item.targetTableName == 'accounts' && item.recordId == account.id,
      ),
      hasLength(3),
    );
  });

  test('blocks deactivation of system accounts', () async {
    final cash = await _accountByName(database, 'Cash');

    expect(
      () => accountsRepository.deactivateAccount(cash.id),
      throwsA(isA<StateError>()),
    );
  });

  test('account balances use active shop for requested user only', () async {
    final now = DateTime.utc(2026, 4, 14);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'user-2',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(
            id: 'shop-2',
            userId: 'user-2',
            name: 'Other Shop',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'other-cash',
            userId: 'user-2',
            shopId: 'shop-2',
            name: 'Other Cash',
            type: 'cash',
            createdAt: now,
            updatedAt: now,
            clientUpdatedAt: now,
          ),
        );

    final balances = await accountsRepository.getAccountBalances(_testUser.id);

    expect(
      balances.any((balance) => balance.account.id == 'other-cash'),
      false,
    );
    expect(balances.any((balance) => balance.account.name == 'Cash'), true);
  });
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
