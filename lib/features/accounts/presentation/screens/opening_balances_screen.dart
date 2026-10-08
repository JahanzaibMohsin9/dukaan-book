import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends ConsumerState<OpeningBalancesScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  bool _isSaving = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Opening balances')),
      body: SafeArea(
        child: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (items) {
            final editable = items
                .where(
                  (item) =>
                      item.account.isActive &&
                      item.account.isSystem &&
                      item.account.type != 'owner_equity',
                )
                .toList(growable: false);

            if (editable.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Create the default accounts before posting balances.',
                  ),
                ),
              );
            }

            for (final item in editable) {
              _controllers.putIfAbsent(
                item.account.id,
                () => TextEditingController(
                  text: item.balancePaisa == 0
                      ? ''
                      : item.balance.format(includeSymbol: false),
                ),
              );
            }

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      border: Border.all(color: AppTheme.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Set the target balance for each account. Only the difference from the current balance is posted, and Owner Equity is updated automatically.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final item in editable) ...[
                    TextFormField(
                      controller: _controllers[item.account.id],
                      enabled: !_isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,\-\sA-Za-z]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: item.account.name,
                        hintText: '0',
                        prefixText: 'PKR ',
                        helperText:
                            'Current: ${item.balance.format(includeSymbol: false)}',
                      ),
                      validator: _validateAmount,
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton(
                    onPressed: _isSaving ? null : () => _save(editable),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Post opening balances'),
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

  String? _validateAmount(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    try {
      MoneyParser.parsePkr(raw);
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

    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      setState(() => _message = 'Sign in again before posting balances.');
      return;
    }

    final drafts = [
      for (final item in accounts)
        OpeningBalanceDraft(
          accountId: item.account.id,
          amount: MoneyParser.parsePkr(
            _controllers[item.account.id]?.text.trim().isEmpty ?? true
                ? '0'
                : _controllers[item.account.id]!.text,
          ),
        ),
    ];

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await ref
          .read(accountsRepositoryProvider)
          .postOpeningBalances(userId: userId, drafts: drafts);
      ref.invalidate(accountBalancesProvider);
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
}
