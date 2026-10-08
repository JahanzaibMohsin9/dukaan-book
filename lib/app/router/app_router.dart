import 'package:dukaan_book/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/account_detail_screen.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/account_form_screen.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/opening_balances_screen.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/auth/presentation/screens/auth_screen.dart';
import 'package:dukaan_book/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:dukaan_book/features/ledger/presentation/screens/entry_screen.dart';
import 'package:dukaan_book/features/ledger/domain/ledger_posting_engine.dart';
import 'package:dukaan_book/features/onboarding/data/onboarding_repository.dart';
import 'package:dukaan_book/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:dukaan_book/features/reports/presentation/screens/reports_screen.dart';
import 'package:dukaan_book/features/settings/presentation/screens/settings_screen.dart';
import 'package:dukaan_book/features/splash/presentation/screens/splash_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum AppRoute {
  splash('/splash', 'Splash'),
  auth('/auth', 'Auth'),
  onboarding('/onboarding', 'Onboarding'),
  dashboard('/dashboard', 'Dashboard'),
  accounts('/accounts', 'Accounts'),
  openingBalances('/accounts/opening-balances', 'Opening Balances'),
  accountCreate('/accounts/new', 'Add Account'),
  entry('/entry', 'Entry'),
  reports('/reports', 'Reports'),
  settings('/settings', 'Settings');

  const AppRoute(this.path, this.label);

  final String path;
  final String label;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authSessionProvider);
  final isSignedIn = authState.hasValue && authState.value != null;
  final isCheckingAuth = authState.isLoading;
  final onboardingState = ref.watch(onboardingCompletedProvider);
  final hasCompletedOnboarding =
      onboardingState.hasValue && onboardingState.value == true;
  final isCheckingOnboarding = isSignedIn && onboardingState.isLoading;

  final router = GoRouter(
    initialLocation: AppRoute.splash.path,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isPublicRoute =
          location == AppRoute.splash.path || location == AppRoute.auth.path;

      if (isCheckingAuth || isCheckingOnboarding) {
        return location == AppRoute.splash.path ? null : AppRoute.splash.path;
      }

      if (!isSignedIn && !isPublicRoute) {
        return AppRoute.auth.path;
      }

      if (isSignedIn &&
          !hasCompletedOnboarding &&
          location != AppRoute.onboarding.path) {
        return AppRoute.onboarding.path;
      }

      if (isSignedIn &&
          hasCompletedOnboarding &&
          (location == AppRoute.splash.path ||
              location == AppRoute.auth.path ||
              location == AppRoute.onboarding.path)) {
        return AppRoute.dashboard.path;
      }

      if (!isSignedIn && location == AppRoute.splash.path) {
        return AppRoute.auth.path;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.name,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.auth.path,
        name: AppRoute.auth.name,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding.path,
        name: AppRoute.onboarding.name,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoute.dashboard.path,
        name: AppRoute.dashboard.name,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: AppRoute.accounts.path,
        name: AppRoute.accounts.name,
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: AppRoute.openingBalances.path,
        name: AppRoute.openingBalances.name,
        builder: (context, state) => const OpeningBalancesScreen(),
      ),
      GoRoute(
        path: AppRoute.accountCreate.path,
        name: AppRoute.accountCreate.name,
        builder: (context, state) => const AccountFormScreen(),
      ),
      GoRoute(
        path: '/accounts/:accountId/edit',
        name: 'accountEdit',
        builder: (context, state) =>
            AccountFormScreen(accountId: state.pathParameters['accountId']),
      ),
      GoRoute(
        path: '/accounts/:accountId',
        name: 'accountDetail',
        builder: (context, state) =>
            AccountDetailScreen(accountId: state.pathParameters['accountId']!),
      ),
      GoRoute(
        path: AppRoute.entry.path,
        name: AppRoute.entry.name,
        builder: (context, state) => EntryScreen(
          initialKind: state.uri.queryParameters['kind'] == 'expense'
              ? LedgerPostingKind.expense
              : LedgerPostingKind.cashIn,
        ),
      ),
      GoRoute(
        path: AppRoute.reports.path,
        name: AppRoute.reports.name,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoute.settings.path,
        name: AppRoute.settings.name,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
