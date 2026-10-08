import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/database/database_provider.dart';
import 'package:dukaan_book/core/id/id_generator.dart';
import 'package:dukaan_book/core/supabase/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final idGeneratorProvider = Provider<IdGenerator>((ref) => IdGenerator());

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    database: ref.watch(appDatabaseProvider),
    supabase: ref.watch(supabaseClientProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

final onboardingCompletedProvider = FutureProvider<bool>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final userId = supabase?.auth.currentUser?.id;
  if (userId == null) {
    return false;
  }

  return ref.watch(onboardingRepositoryProvider).isComplete(userId);
});

class OnboardingRepository {
  const OnboardingRepository({
    required this.database,
    required this.supabase,
    required this.idGenerator,
  });

  final AppDatabase database;
  final SupabaseClient? supabase;
  final IdGenerator idGenerator;

  Future<bool> isComplete(String userId) async {
    final setting =
        await (database.select(database.appSettings)
              ..where((row) => row.key.equals(_onboardingKey(userId))))
            .getSingleOrNull();
    if (setting?.value == 'true') {
      return true;
    }

    final membership =
        await (database.select(database.shopMembers)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.deletedAt.isNull()))
            .getSingleOrNull();
    if (membership != null) {
      return true;
    }

    final shop =
        await (database.select(database.shops)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.deletedAt.isNull()))
            .getSingleOrNull();
    return shop != null;
  }

  Future<void> completeShopSetup({
    required User user,
    required String shopName,
    String? ownerName,
    String? city,
    String? phone,
  }) async {
    final now = DateTime.now().toUtc();
    final trimmedOwnerName = _nullableTrim(ownerName);
    final trimmedCity = _nullableTrim(city);
    final trimmedPhone = _nullableTrim(phone);
    final shopId = idGenerator.next();
    final membership = ShopMembersCompanion.insert(
      id: idGenerator.next(),
      shopId: shopId,
      userId: user.id,
      role: const Value('owner'),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    );
    final accounts = _defaultAccounts(user.id, shopId, now);
    final categories = _defaultExpenseCategories(user.id, shopId, now);

    await database.transaction(() async {
      await database
          .into(database.profiles)
          .insertOnConflictUpdate(
            ProfilesCompanion(
              id: Value(user.id),
              fullName: Value(trimmedOwnerName),
              phone: Value(trimmedPhone),
              preferredLanguage: const Value('en'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.shops)
          .insertOnConflictUpdate(
            ShopsCompanion(
              id: Value(shopId),
              userId: Value(user.id),
              name: Value(shopName.trim()),
              city: Value(trimmedCity),
              phone: Value(trimmedPhone),
              timezone: const Value('Asia/Karachi'),
              dayCloseTime: const Value('21:00'),
              createdAt: Value(now),
              updatedAt: Value(now),
              deletedAt: const Value(null),
            ),
          );
      await database
          .into(database.shopMembers)
          .insertOnConflictUpdate(membership);

      for (final account in accounts) {
        await database.into(database.accounts).insertOnConflictUpdate(account);
      }

      for (final category in categories) {
        await database
            .into(database.expenseCategories)
            .insertOnConflictUpdate(category);
      }

      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion(
              key: Value(_onboardingKey(user.id)),
              value: const Value('true'),
              updatedAt: Value(now),
            ),
          );
      await _queueOutbox(
        table: 'profiles',
        recordId: user.id,
        payload: {
          'id': user.id,
          'full_name': trimmedOwnerName,
          'phone': trimmedPhone,
          'preferred_language': 'en',
        },
        now: now,
      );
      await _queueOutbox(
        table: 'shops',
        recordId: shopId,
        payload: {
          'id': shopId,
          'user_id': user.id,
          'name': shopName.trim(),
          'city': trimmedCity,
          'phone': trimmedPhone,
          'timezone': 'Asia/Karachi',
          'day_close_time': '21:00',
        },
        now: now,
      );
      await _queueOutbox(
        table: 'shop_members',
        recordId: membership.id.value,
        payload: _membershipPayload(membership),
        now: now,
      );
      for (final account in accounts) {
        await _queueOutbox(
          table: 'accounts',
          recordId: account.id.value,
          payload: _accountPayload(account),
          now: now,
        );
      }
      for (final category in categories) {
        await _queueOutbox(
          table: 'expense_categories',
          recordId: category.id.value,
          payload: _categoryPayload(category),
          now: now,
        );
      }
    });

    await _pushToSupabase(
      user: user,
      shopId: shopId,
      shopName: shopName.trim(),
      ownerName: trimmedOwnerName,
      city: trimmedCity,
      phone: trimmedPhone,
      membership: membership,
      accounts: accounts,
      categories: categories,
    );
  }

  Future<void> joinExistingShop({
    required User user,
    required String shopId,
    String? ownerName,
    String? phone,
  }) async {
    final client = supabase;
    if (client == null) {
      throw StateError('Cloud sync is required to join a shared shop.');
    }

    final now = DateTime.now().toUtc();
    final trimmedShopId = shopId.trim();
    final trimmedOwnerName = _nullableTrim(ownerName);
    final trimmedPhone = _nullableTrim(phone);
    final membership = ShopMembersCompanion.insert(
      id: idGenerator.next(),
      shopId: trimmedShopId,
      userId: user.id,
      role: const Value('staff'),
      createdAt: now,
      updatedAt: now,
      clientUpdatedAt: now,
    );

    final bootstrap = _rpcObject(
      await client.rpc(
        'join_shop',
        params: {
          'p_shop_id': trimmedShopId,
          'p_full_name': trimmedOwnerName,
          'p_phone': trimmedPhone,
          'p_membership_id': membership.id.value,
        },
      ),
    );

    final shopRow = _rpcObject(bootstrap['shop']);
    final membershipRow = _rpcObject(bootstrap['membership']);
    final accountRows = _rpcRows(bootstrap['accounts']);
    final categoryRows = _rpcRows(bootstrap['expense_categories']);

    await database.transaction(() async {
      await database
          .into(database.profiles)
          .insertOnConflictUpdate(
            ProfilesCompanion(
              id: Value(user.id),
              fullName: Value(trimmedOwnerName),
              phone: Value(trimmedPhone),
              preferredLanguage: const Value('en'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final shopOwnerId = shopRow['user_id'] as String;
      if (shopOwnerId != user.id) {
        await database
            .into(database.profiles)
            .insertOnConflictUpdate(
              ProfilesCompanion.insert(
                id: shopOwnerId,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      await database
          .into(database.shops)
          .insertOnConflictUpdate(_shopCompanion(shopRow));
      await database
          .into(database.shopMembers)
          .insertOnConflictUpdate(_memberCompanion(membershipRow));
      for (final row in accountRows) {
        await database
            .into(database.accounts)
            .insertOnConflictUpdate(_accountCompanion(row));
      }
      for (final row in categoryRows) {
        await database
            .into(database.expenseCategories)
            .insertOnConflictUpdate(_categoryCompanion(row));
      }
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion(
              key: Value(_onboardingKey(user.id)),
              value: const Value('true'),
              updatedAt: Value(now),
            ),
          );
    });
  }

  Future<void> _pushToSupabase({
    required User user,
    required String shopId,
    required String shopName,
    required String? ownerName,
    required String? city,
    required String? phone,
    required ShopMembersCompanion membership,
    required List<AccountsCompanion> accounts,
    required List<ExpenseCategoriesCompanion> categories,
  }) async {
    final client = supabase;
    if (client == null) {
      return;
    }

    await client.from('profiles').upsert({
      'id': user.id,
      'full_name': ownerName,
      'phone': phone,
      'preferred_language': 'en',
    });
    await client.from('shops').upsert({
      'id': shopId,
      'user_id': user.id,
      'name': shopName,
      'city': city,
      'phone': phone,
      'timezone': 'Asia/Karachi',
      'day_close_time': '21:00',
    });
    await client.from('shop_members').upsert(_membershipPayload(membership));
    await client
        .from('accounts')
        .upsert(accounts.map(_accountPayload).toList());
    await client
        .from('expense_categories')
        .upsert(categories.map(_categoryPayload).toList());
  }

  List<AccountsCompanion> _defaultAccounts(
    String userId,
    String shopId,
    DateTime now,
  ) {
    const defaults = [
      ('Cash', 'cash', '#2F6B45'),
      ('EasyPaisa', 'easypaisa', '#7AC143'),
      ('JazzCash', 'jazzcash', '#D71920'),
      ('NayaPay', 'nayapay', '#2563EB'),
      ('Bank', 'bank', '#17211B'),
      ('Owner Equity', 'owner_equity', '#D86F45'),
    ];

    return [
      for (var index = 0; index < defaults.length; index++)
        AccountsCompanion(
          id: Value(idGenerator.next()),
          userId: Value(userId),
          shopId: Value(shopId),
          name: Value(defaults[index].$1),
          type: Value(defaults[index].$2),
          colorHex: Value(defaults[index].$3),
          sortOrder: Value(index),
          isActive: const Value(true),
          isSystem: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
          deletedAt: const Value(null),
          clientUpdatedAt: Value(now),
        ),
    ];
  }

  List<ExpenseCategoriesCompanion> _defaultExpenseCategories(
    String userId,
    String shopId,
    DateTime now,
  ) {
    const defaults = [
      ('Rent', 'storefront'),
      ('Electricity', 'bolt'),
      ('Internet', 'wifi'),
      ('Supplies', 'inventory_2'),
      ('Staff', 'groups'),
      ('Other', 'more_horiz'),
    ];

    return [
      for (var index = 0; index < defaults.length; index++)
        ExpenseCategoriesCompanion(
          id: Value(idGenerator.next()),
          userId: Value(userId),
          shopId: Value(shopId),
          name: Value(defaults[index].$1),
          icon: Value(defaults[index].$2),
          sortOrder: Value(index),
          isSystem: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
          deletedAt: const Value(null),
          clientUpdatedAt: Value(now),
        ),
    ];
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

  static Map<String, Object?> _membershipPayload(
    ShopMembersCompanion membership,
  ) {
    return {
      'id': membership.id.value,
      'shop_id': membership.shopId.value,
      'user_id': membership.userId.value,
      'role': membership.role.present ? membership.role.value : 'staff',
      'client_updated_at': membership.clientUpdatedAt.value.toIso8601String(),
    };
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

  static DateTime? _date(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
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

  static Map<String, Object?> _rpcObject(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    throw const FormatException('Unexpected join shop response.');
  }

  static List<Map<String, Object?>> _rpcRows(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      return [
        for (final row in value)
          if (row is Map) Map<String, Object?>.from(row),
      ];
    }
    throw const FormatException('Unexpected join shop rows.');
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

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _queueOutbox({
    required String table,
    required String recordId,
    required Map<String, Object?> payload,
    required DateTime now,
  }) {
    return database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            id: idGenerator.next(),
            targetTableName: table,
            recordId: recordId,
            operation: 'upsert',
            payloadJson: jsonEncode(payload),
            createdAt: now,
          ),
        );
  }

  static String _onboardingKey(String userId) => 'onboarding_complete:$userId';
}
