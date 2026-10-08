import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/database/app_database.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  static const _colors = [
    '#2F6B45',
    '#D86F45',
    '#2563EB',
    '#8A5A44',
    '#5B8C5A',
    '#B91C1C',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController(text: 'custom');
  final _thresholdController = TextEditingController();
  String _colorHex = _colors.first;
  bool _loaded = false;
  bool _isSaving = false;
  String? _message;

  bool get _isEditing => widget.accountId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountFuture = _isEditing
        ? ref.watch(_accountProvider(widget.accountId!))
        : const AsyncData(null);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit account' : 'Add account')),
      body: SafeArea(
        child: accountFuture.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (account) {
            if (_isEditing && account == null) {
              return const Center(child: Text('Account not found.'));
            }
            if (!_loaded && account != null) {
              _nameController.text = account.name;
              _typeController.text = account.type;
              _thresholdController.text =
                  account.lowBalanceThresholdPaisa == null
                  ? ''
                  : Money.fromPaisa(
                      account.lowBalanceThresholdPaisa!,
                    ).format(includeSymbol: false);
              _colorHex = account.colorHex ?? _colorHex;
              _loaded = true;
            }

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Account name',
                      hintText: 'Supplier wallet',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().length < 2) {
                        return 'Account name is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _typeController,
                    enabled: !_isSaving && !(account?.isSystem ?? false),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      hintText: 'custom, wallet, bank, savings',
                    ),
                    validator: (value) {
                      final trimmed = (value ?? '').trim();
                      if (trimmed.length < 2) {
                        return 'Type is required.';
                      }
                      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(trimmed)) {
                        return 'Use lowercase letters, numbers, and underscores.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Color',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final color in _colors)
                        _ColorChoice(
                          colorHex: color,
                          selected: _colorHex == color,
                          onTap: _isSaving
                              ? null
                              : () => setState(() => _colorHex = color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _thresholdController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,\-\sA-Za-z]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Low-balance threshold',
                      hintText: 'Optional',
                      prefixText: 'PKR ',
                    ),
                    validator: _validateOptionalAmount,
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isEditing ? 'Save account' : 'Create account',
                            ),
                    ),
                  ),
                  if (_isEditing && account != null && !account.isSystem) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _deactivate(account.id, account.name),
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Deactivate account'),
                    ),
                  ],
                  if (_isEditing && (account?.isSystem ?? false)) ...[
                    const SizedBox(height: 12),
                    const _SystemNotice(),
                  ],
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

  String? _validateOptionalAmount(String? value) {
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final thresholdText = _thresholdController.text.trim();
    final write = AccountWrite(
      name: _nameController.text,
      type: _typeController.text,
      colorHex: _colorHex,
      lowBalanceThreshold: thresholdText.isEmpty
          ? null
          : MoneyParser.parsePkr(thresholdText),
    );

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final repository = ref.read(accountsRepositoryProvider);
      if (_isEditing) {
        await repository.updateAccount(
          accountId: widget.accountId!,
          write: write,
        );
      } else {
        final userId = ref.read(authRepositoryProvider).currentUser?.id;
        if (userId == null) {
          throw StateError('Sign in again before creating an account.');
        }
        await repository.createAccount(userId: userId, write: write);
      }
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

  Future<void> _deactivate(String accountId, String accountName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: Text(
          '$accountName will stay in history but stop appearing as active.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(accountsRepositoryProvider).deactivateAccount(accountId);
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

final _accountProvider = FutureProvider.autoDispose.family<Account?, String>((
  ref,
  accountId,
) {
  return ref.watch(accountsRepositoryProvider).getAccount(accountId);
});

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  final String colorHex;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse(colorHex.substring(1), radix: 16) | 0xFF000000,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.ink : AppTheme.line,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : null,
      ),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'System accounts can be renamed and recolored, but they cannot be deactivated.',
        ),
      ),
    );
  }
}
