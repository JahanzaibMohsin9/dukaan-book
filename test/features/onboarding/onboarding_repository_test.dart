import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late OnboardingRepository repository;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = OnboardingRepository(
      database: database,
      supabase: null,
      idGenerator: IdGenerator(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'creates profile, shop, default accounts, and categories locally',
    () async {
      await repository.completeShopSetup(
        user: _testUser,
        shopName: '  Jahan Mobile Shop  ',
        ownerName: ' Jahan ',
        city: ' Lahore ',
        phone: ' 0300 0000000 ',
      );

      final profiles = await database.select(database.profiles).get();
      final shops = await database.select(database.shops).get();
      final accounts = await database.select(database.accounts).get();
      final categories = await database
          .select(database.expenseCategories)
          .get();

      expect(profiles.single.id, 'user-1');
      expect(profiles.single.fullName, 'Jahan');
      expect(shops.single.name, 'Jahan Mobile Shop');
      expect(shops.single.timezone, 'Asia/Karachi');
      expect(accounts.map((account) => account.name), contains('Cash'));
      expect(accounts.map((account) => account.name), contains('Owner Equity'));
      expect(accounts.every((account) => account.isSystem), isTrue);
      expect(categories.map((category) => category.name), contains('Rent'));
      expect(categories.map((category) => category.name), contains('Other'));
      expect(categories.every((category) => category.isSystem), isTrue);
    },
  );

  test('does not repeat onboarding after completion', () async {
    expect(await repository.isComplete(_testUser.id), isFalse);

    await repository.completeShopSetup(user: _testUser, shopName: 'Demo Shop');

    expect(await repository.isComplete(_testUser.id), isTrue);
  });
}

const _testUser = User(
  id: 'user-1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  email: 'owner@example.com',
  createdAt: '2026-04-13T00:00:00Z',
);
