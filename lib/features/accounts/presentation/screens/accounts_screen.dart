import 'package:dukaan_book/app/router/app_router.dart';
import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final accountBalancesProvider =
    StreamProvider.autoDispose<List<AccountBalance>>((ref) {
      final userId = ref.watch(authRepositoryProvider).currentUser?.id;
      if (userId == null) {
        return Stream.value(const []);
      }
      return ref.watch(accountsRepositoryProvider).watchAccountBalances(userId);
    });

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountBalancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Opening balances',
            onPressed: () => context.push(AppRoute.openingBalances.path),
            icon: const Icon(Icons.account_balance_wallet_rounded),
          ),
          IconButton(
            tooltip: 'Add account',
            onPressed: () => context.push(AppRoute.accountCreate.path),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: accounts.when(
          loading: () => const _AccountsLoading(),
          error: (error, stackTrace) => _AccountsMessage(
            icon: Icons.error_outline_rounded,
            title: 'Accounts could not load',
            body: error.toString(),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _AccountsMessage(
                icon: Icons.wallet_rounded,
                title: 'No accounts yet',
                body:
                    'Create your shop ledger first, then Cash, wallets, bank, and custom accounts will appear here.',
              );
            }

            final active = items
                .where((item) => item.account.isActive)
                .toList(growable: false);
            final inactive = items
                .where((item) => !item.account.isActive)
                .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _AccountsHeader(accounts: active),
                const SizedBox(height: 18),
                for (final item in active) _AccountTile(item: item),
                if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Inactive',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final item in inactive) _AccountTile(item: item),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    final total = accounts
        .where((item) => item.account.type != 'owner_equity')
        .fold<int>(0, (sum, item) => sum + item.balancePaisa);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available balance',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Money.fromPaisa(total).format(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${accounts.length} active accounts',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.item});

  final AccountBalance item;

  @override
  Widget build(BuildContext context) {
    final account = item.account;
    final color = _parseColor(account.colorHex) ?? AppTheme.leaf;
    final titleColor = account.isActive ? AppTheme.ink : Colors.black45;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/accounts/${account.id}'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: account.isActive ? Colors.white : const Color(0xFFF2F4EF),
            border: Border.all(color: AppTheme.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: account.isActive ? 0.16 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _typeIcon(account.type),
                    color: account.isActive ? color : Colors.black38,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_typeLabel(account.type)} - ${account.isActive ? 'Active' : 'Inactive'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: account.isActive
                              ? Colors.black54
                              : Colors.black38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.balance.format(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (item.isLowBalance) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Low',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.clay,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountsLoading extends StatelessWidget {
  const _AccountsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: const [
        _LoadingBlock(height: 120),
        SizedBox(height: 18),
        _LoadingBlock(height: 72),
        SizedBox(height: 12),
        _LoadingBlock(height: 72),
        SizedBox(height: 12),
        _LoadingBlock(height: 72),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(height: height),
    );
  }
}

class _AccountsMessage extends StatelessWidget {
  const _AccountsMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.leaf),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Color? _parseColor(String? value) {
  if (value == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
}

IconData _typeIcon(String type) {
  return switch (type) {
    'cash' => Icons.payments_rounded,
    'bank' => Icons.account_balance_rounded,
    'owner_equity' => Icons.foundation_rounded,
    'easypaisa' || 'jazzcash' || 'nayapay' => Icons.phone_android_rounded,
    _ => Icons.account_balance_wallet_rounded,
  };
}

String _typeLabel(String type) {
  return type
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
