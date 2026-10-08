import 'dart:async';

import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/ledger/data/ledger_repository.dart';
import 'package:dukaan_book/features/ledger/domain/ledger_posting_engine.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key, this.initialKind = LedgerPostingKind.cashIn});

  final LedgerPostingKind initialKind;

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _serviceChargeController = TextEditingController();
  final _noteController = TextEditingController();
  final _referenceController = TextEditingController();
  final _newCategoryController = TextEditingController();
  late LedgerPostingKind _kind;
  String? _accountId;
  String? _fromAccountId;
  String? _toAccountId;
  String? _paymentAccountId;
  String? _categoryId;
  bool _isSaving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _serviceChargeController.dispose();
    _noteController.dispose();
    _referenceController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountBalancesProvider);
    final categories = ref.watch(expenseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New entry')),
      body: SafeArea(
        child: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (accountItems) {
            final activeAccounts = accountItems
                .where(
                  (item) =>
                      item.account.isActive &&
                      item.account.type != 'owner_equity' &&
                      item.account.type != 'expense_bucket',
                )
                .toList(growable: false);

            if (activeAccounts.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Create at least one active cash, wallet, or bank account before posting entries.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            _accountId ??= activeAccounts.first.account.id;
            _fromAccountId ??= activeAccounts.first.account.id;
            _toAccountId ??= activeAccounts.length > 1
                ? activeAccounts[1].account.id
                : activeAccounts.first.account.id;
            _paymentAccountId ??= activeAccounts.first.account.id;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _KindSelector(
                    selected: _kind,
                    onSelected: _isSaving
                        ? null
                        : (kind) => setState(() {
                            _kind = kind;
                            _message = null;
                          }),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _amountController,
                    enabled: !_isSaving,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,\-\sA-Za-z]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      hintText: '0',
                      prefixText: 'PKR ',
                    ),
                    validator: _validateAmount,
                  ),
                  const SizedBox(height: 14),
                  ..._kindFields(activeAccounts, categories),
                  TextFormField(
                    controller: _noteController,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _referenceController,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Reference',
                      hintText: 'Receipt, sender, or short code',
                    ),
                    onFieldSubmitted: (_) => _save(activeAccounts),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _isSaving ? null : () => _save(activeAccounts),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save entry'),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _message!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.clay,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _kindFields(
    List<AccountBalance> accounts,
    AsyncValue<List<ExpenseCategory>> categories,
  ) {
    return switch (_kind) {
      LedgerPostingKind.cashIn ||
      LedgerPostingKind.cashOut ||
      LedgerPostingKind.adjustment => [
        _AccountDropdown(
          label: 'Account',
          value: _accountId,
          accounts: accounts,
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _accountId = value),
        ),
        const SizedBox(height: 14),
      ],
      LedgerPostingKind.transfer => [
        _AccountDropdown(
          label: 'From account',
          value: _fromAccountId,
          accounts: accounts,
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _fromAccountId = value),
        ),
        const SizedBox(height: 14),
        _AccountDropdown(
          label: 'To account',
          value: _toAccountId,
          accounts: accounts,
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _toAccountId = value),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _serviceChargeController,
          enabled: !_isSaving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\sA-Za-z]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Service charge / profit',
            hintText: 'Optional, e.g. 10',
            prefixText: 'PKR ',
          ),
          validator: _validateServiceCharge,
        ),
        const SizedBox(height: 14),
      ],
      LedgerPostingKind.expense => [
        _AccountDropdown(
          label: 'Paid from',
          value: _paymentAccountId,
          accounts: accounts,
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _paymentAccountId = value),
        ),
        const SizedBox(height: 14),
        categories.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stackTrace) => Text(error.toString()),
          data: (items) {
            _categoryId ??= items.isEmpty
                ? _newCategorySentinel
                : items.first.id;
            return DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in items)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                const DropdownMenuItem(
                  value: _newCategorySentinel,
                  child: Text('Add new category'),
                ),
              ],
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _categoryId = value),
            );
          },
        ),
        const SizedBox(height: 14),
        if (_categoryId == _newCategorySentinel)
          TextFormField(
            controller: _newCategoryController,
            enabled: !_isSaving,
            decoration: const InputDecoration(
              labelText: 'New category name',
              hintText: 'Fuel, delivery, repairs',
            ),
            validator: (value) {
              if (_kind != LedgerPostingKind.expense ||
                  _categoryId != _newCategorySentinel) {
                return null;
              }
              if ((value ?? '').trim().length < 2) {
                return 'Category name is required.';
              }
              return null;
            },
          ),
        if (_categoryId == _newCategorySentinel) const SizedBox(height: 14),
      ],
    };
  }

  String? _validateAmount(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return 'Amount is required.';
    }
    try {
      final amount = MoneyParser.parsePkr(raw);
      if (amount.isZero) {
        return 'Amount must be non-zero.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateServiceCharge(String? value) {
    if (_kind != LedgerPostingKind.transfer) {
      return null;
    }
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    try {
      final amount = MoneyParser.parsePkr(raw);
      if (amount.isNegative) {
        return 'Service charge cannot be negative.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _save(List<AccountBalance> accounts) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_kind == LedgerPostingKind.transfer && _fromAccountId == _toAccountId) {
      setState(() => _message = 'Choose two different accounts.');
      return;
    }

    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      setState(() => _message = 'Sign in again before saving an entry.');
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await ref
          .read(ledgerRepositoryProvider)
          .postEntry(
            userId: userId,
            write: LedgerEntryWrite(
              kind: _kind,
              amount: MoneyParser.parsePkr(_amountController.text),
              serviceCharge: _kind == LedgerPostingKind.transfer
                  ? _parseOptionalMoney(_serviceChargeController.text)
                  : null,
              accountId: _accountId,
              fromAccountId: _fromAccountId,
              toAccountId: _toAccountId,
              paymentAccountId: _paymentAccountId,
              expenseCategoryId: _categoryId == _newCategorySentinel
                  ? null
                  : _categoryId,
              newExpenseCategoryName: _categoryId == _newCategorySentinel
                  ? _newCategoryController.text
                  : null,
              note: _noteController.text,
              externalRef: _referenceController.text,
            ),
          );
      unawaited(ref.read(syncServiceProvider).syncNow(userId: userId));
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(latestActivityProvider);
      ref.invalidate(todayNetChangeProvider);
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Money? _parseOptionalMoney(String value) {
    final raw = value.trim();
    return raw.isEmpty ? null : MoneyParser.parsePkr(raw);
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onSelected});

  final LedgerPostingKind selected;
  final ValueChanged<LedgerPostingKind>? onSelected;

  @override
  Widget build(BuildContext context) {
    const kinds = [
      LedgerPostingKind.cashIn,
      LedgerPostingKind.cashOut,
      LedgerPostingKind.transfer,
      LedgerPostingKind.expense,
      LedgerPostingKind.adjustment,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in kinds)
          ChoiceChip(
            label: Text(_kindLabel(kind)),
            selected: selected == kind,
            onSelected: onSelected == null
                ? null
                : (_) => onSelected?.call(kind),
          ),
      ],
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<AccountBalance> accounts;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in accounts)
          DropdownMenuItem(
            value: item.account.id,
            child: Text('${item.account.name} (${item.balance.format()})'),
          ),
      ],
      validator: (value) =>
          value == null || value.isEmpty ? '$label is required.' : null,
      onChanged: onChanged,
    );
  }
}

String _kindLabel(LedgerPostingKind kind) {
  return switch (kind) {
    LedgerPostingKind.cashIn => 'Cash in',
    LedgerPostingKind.cashOut => 'Cash out',
    LedgerPostingKind.transfer => 'Transfer',
    LedgerPostingKind.expense => 'Expense',
    LedgerPostingKind.adjustment => 'Adjust',
  };
}

const _newCategorySentinel = '__new_category__';
