import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/auth/presentation/controllers/auth_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _AuthMode { signIn, signUp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    final formState = ref.watch(authFormControllerProvider);
    final isBusy = formState.isLoading;

    ref.listen<AsyncValue<void>>(authFormControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _message = _mode == _AuthMode.signUp
                ? 'Account created. If email confirmation is enabled, confirm it before signing in.'
                : null;
          });
        },
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
            const _BrandMark(),
            const SizedBox(height: 28),
            Text(
              _mode == _AuthMode.signIn
                  ? 'Open your ledger'
                  : 'Start the ledger',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _mode == _AuthMode.signIn
                  ? 'Sign in before the first sale, then keep working even when the internet disappears.'
                  : 'Create your shopkeeper account. The local ledger stays ready for offline work.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 24),
            _ModeSwitch(
              mode: _mode,
              onChanged: (mode) {
                setState(() {
                  _mode = mode;
                  _message = null;
                });
              },
            ),
            const SizedBox(height: 18),
            if (!repository.isConfigured) ...[
              const _Notice(
                title: 'Supabase is not ready',
                body:
                    'Add Supabase values locally. For APK builds, pass SUPABASE_URL and SUPABASE_ANON_KEY with Dart defines.',
              ),
              const SizedBox(height: 18),
            ],
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    enabled: !isBusy && repository.isConfigured,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@shop.com',
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !isBusy && repository.isConfigured,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 6 characters',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isBusy || !repository.isConfigured ? null : _submit,
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
                          key: ValueKey(_mode),
                          _mode == _AuthMode.signIn
                              ? 'Sign in'
                              : 'Create account',
                        ),
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              _Notice(title: 'Auth update', body: _message!),
            ],
            const SizedBox(height: 28),
            const _TrustStrip(),
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

    final controller = ref.read(authFormControllerProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_mode == _AuthMode.signIn) {
      await controller.signIn(email: email, password: password);
    } else {
      await controller.signUp(email: email, password: password);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required.';
    }
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is AuthConfigException) {
      return 'Supabase keys are missing. Add them locally, then restart the app. For APK builds, pass them with Dart defines.';
    }
    if (error is AuthException) {
      return error.message;
    }
    return 'Could not complete auth. Check your internet and try again.';
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.leaf,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox(
            height: 44,
            width: 44,
            child: Icon(Icons.receipt_long_rounded, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dukaan Book',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              'Cash, wallet, bank',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.leaf,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _ModeButton(
            label: 'Sign in',
            selected: mode == _AuthMode.signIn,
            onTap: () => onChanged(_AuthMode.signIn),
          ),
          _ModeButton(
            label: 'Sign up',
            selected: mode == _AuthMode.signUp,
            onTap: () => onChanged(_AuthMode.signUp),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppTheme.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : AppTheme.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.leaf,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(body),
          ],
        ),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.wifi_off_rounded, 'Offline first'),
      (Icons.lock_outline_rounded, 'Private rows'),
      (Icons.payments_outlined, 'Paisa safe'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppTheme.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$1, size: 18, color: AppTheme.clay),
                  const SizedBox(width: 8),
                  Text(
                    item.$2,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
