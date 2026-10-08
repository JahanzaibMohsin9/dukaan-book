import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _joinShopIdController = TextEditingController();

  bool _isJoining = false;
  String? _message;

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _joinShopIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final isBusy = state.isLoading;

    ref.listen<AsyncValue<void>>(onboardingControllerProvider, (
      previous,
      next,
    ) {
      next.whenOrNull(
        error: (error, stackTrace) {
          if (!mounted) {
            return;
          }
          setState(() {
            _message = _friendlyError(error);
          });
        },
      );
    });

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const _LedgerStrip(),
            const SizedBox(height: 26),
            Text(
              'Name the shop',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Set up the first ledger once. Cash, wallets, bank, owner equity, and expense categories will be ready before the first entry.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Create shop'),
                  icon: Icon(Icons.add_business_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Join shop'),
                  icon: Icon(Icons.group_add_rounded),
                ),
              ],
              selected: {_isJoining},
              onSelectionChanged: isBusy
                  ? null
                  : (values) => setState(() {
                      _isJoining = values.first;
                      _message = null;
                    }),
            ),
            const SizedBox(height: 18),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_isJoining) ...[
                    TextFormField(
                      controller: _joinShopIdController,
                      enabled: !isBusy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Shared shop ID',
                        hintText: 'Paste the shop ID from Settings',
                      ),
                      validator: (value) {
                        if (!_isJoining) {
                          return null;
                        }
                        if ((value ?? '').trim().length < 8) {
                          return 'Shared shop ID is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    TextFormField(
                      controller: _shopNameController,
                      enabled: !isBusy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Shop name',
                        hintText: 'Jahan Mobile Shop',
                      ),
                      validator: (value) {
                        if (_isJoining) {
                          return null;
                        }
                        if ((value ?? '').trim().length < 2) {
                          return 'Shop name is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _ownerNameController,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Owner name',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _cityController,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      hintText: 'Lahore',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: 'Optional',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_isJoining) const _JoinPreview() else const _DefaultsPreview(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isBusy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: isBusy
                      ? const SizedBox.square(
                          key: ValueKey('busy'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isJoining
                              ? 'Join shared shop'
                              : 'Create shop ledger',
                          key: ValueKey(_isJoining),
                        ),
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              _Notice(text: _message!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _message = null;
    });

    final controller = ref.read(onboardingControllerProvider.notifier);
    if (_isJoining) {
      await controller.joinExistingShop(
        shopId: _joinShopIdController.text,
        ownerName: _ownerNameController.text,
        phone: _phoneController.text,
      );
    } else {
      await controller.completeShopSetup(
        shopName: _shopNameController.text,
        ownerName: _ownerNameController.text,
        city: _cityController.text,
        phone: _phoneController.text,
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is OnboardingAuthException) {
      return 'Sign in again before creating the shop ledger.';
    }
    if (error is PostgrestException) {
      return error.message;
    }
    if (_isJoining) {
      return 'Could not join the shared shop. Check the shop ID and connection, then try again.';
    }
    return 'Could not create the shop ledger. Check the connection and try again.';
  }
}

class _LedgerStrip extends StatelessWidget {
  const _LedgerStrip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.storefront_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'One shop. One clean ledger. Ready offline.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultsPreview extends StatelessWidget {
  const _DefaultsPreview();

  @override
  Widget build(BuildContext context) {
    const accounts = ['Cash', 'EasyPaisa', 'JazzCash', 'NayaPay', 'Bank'];
    const expenses = ['Rent', 'Electricity', 'Internet', 'Supplies', 'Staff'];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created automatically',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _ChipWrap(label: 'Accounts', values: accounts),
            const SizedBox(height: 12),
            _ChipWrap(label: 'Expenses', values: expenses),
          ],
        ),
      ),
    );
  }
}

class _JoinPreview extends StatelessWidget {
  const _JoinPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sync_rounded, color: AppTheme.leaf),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Join the same shop ledger. Accounts, categories, balances, and entries will sync with the other devices.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.leaf,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.clay),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
