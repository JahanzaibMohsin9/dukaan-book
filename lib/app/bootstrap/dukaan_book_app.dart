import 'package:dukaan_book/app/router/app_router.dart';
import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/features/notifications/data/notification_service.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DukaanBookApp extends ConsumerWidget {
  const DukaanBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.watch(autoSyncProvider);
    ref.watch(notificationAutomationProvider);

    return MaterialApp.router(
      title: 'Dukaan Book',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
