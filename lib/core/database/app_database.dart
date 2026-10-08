import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

const appDatabaseFileName = 'dukaan_book.sqlite';

class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get preferredLanguage =>
      text().withDefault(const Constant('en'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Shops extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get name => text()();
  TextColumn get city => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Karachi'))();
  TextColumn get dayCloseTime => text().withDefault(const Constant('21:00'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShopMembers extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get role => text().withDefault(const Constant('staff'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get colorHex => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get lowBalanceThresholdPaisa => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LedgerTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get kind => text()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  DateTimeColumn get businessDate => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get externalRef => text().nullable()();
  TextColumn get reversedTransactionId =>
      text().nullable().references(LedgerTransactions, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LedgerLines extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get transactionId => text().references(LedgerTransactions, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amountPaisa =>
      integer().customConstraint('NOT NULL CHECK (amount_paisa <> 0)')();
  TextColumn get memo => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DailyClosings extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Profiles, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  DateTimeColumn get businessDate => dateTime()();
  IntColumn get totalInPaisa => integer()();
  IntColumn get totalOutPaisa => integer()();
  IntColumn get totalExpensePaisa => integer()();
  IntColumn get netChangePaisa => integer()();
  TextColumn get closingSnapshotJson => text()();
  DateTimeColumn get closedAt => dateTime()();
  DateTimeColumn get reopenedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get clientUpdatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get targetTableName => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Profiles,
    Shops,
    ShopMembers,
    Accounts,
    LedgerTransactions,
    LedgerLines,
    ExpenseCategories,
    DailyClosings,
    SyncOutbox,
    SyncState,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await customStatement(
          'CREATE UNIQUE INDEX daily_closings_unique_day_idx '
          'ON daily_closings (shop_id, business_date) '
          'WHERE deleted_at IS NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX shop_members_user_shop_idx '
          'ON shop_members (user_id, shop_id) '
          'WHERE deleted_at IS NULL',
        );
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(shopMembers);
          await customStatement(
            'CREATE UNIQUE INDEX shop_members_user_shop_idx '
            'ON shop_members (user_id, shop_id) '
            'WHERE deleted_at IS NULL',
          );
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, appDatabaseFileName));
    return NativeDatabase.createInBackground(file, logStatements: kDebugMode);
  });
}
