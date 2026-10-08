import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates local database and inserts an account', () async {
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

    final accounts = await database.select(database.accounts).get();

    expect(accounts, hasLength(1));
    expect(accounts.single.name, 'Cash');
    expect(accounts.single.isActive, isTrue);
  });

  test('tracks migration schema version', () {
    expect(database.schemaVersion, 2);
  });

  test('opens the same database after closing and reopening', () async {
    final directory = await Directory.systemTemp.createTemp('dukaan_book_db_');
    final file = File('${directory.path}/restart.sqlite');
    final now = DateTime.utc(2026, 4, 13);

    final firstConnection = AppDatabase(NativeDatabase(file));
    await firstConnection
        .into(firstConnection.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'user-restart',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await firstConnection.close();

    final secondConnection = AppDatabase(NativeDatabase(file));
    final profiles = await secondConnection
        .select(secondConnection.profiles)
        .get();

    expect(profiles.single.id, 'user-restart');

    await secondConnection.close();
    await directory.delete(recursive: true);
  });
}
