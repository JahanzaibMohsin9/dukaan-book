import 'dart:math' as math;

import 'package:dukaan_book/app/router/app_router.dart';
import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/features/accounts/data/accounts_repository.dart';
import 'package:dukaan_book/features/accounts/presentation/screens/accounts_screen.dart';
import 'package:dukaan_book/features/ledger/data/ledger_repository.dart';
import 'package:dukaan_book/features/sync/data/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountBalancesProvider);
    final todayNet = ref.watch(todayNetChangeProvider);
    final activity = ref.watch(latestActivityProvider);
    final weeklySummary = ref.watch(weeklySummaryProvider);
    final monthlyExpenses = ref.watch(monthlyExpenseSummaryProvider);
    final balanceTrend = ref.watch(balanceTrendProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          syncStatus.maybeWhen(
            data: (status) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Center(child: _SyncBadge(status: status)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoute.settings.path),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: (items) {
            final visible = items
                .where(
                  (item) =>
                      item.account.isActive &&
                      item.account.type != 'owner_equity',
                )
                .toList(growable: false);
            final total = visible.fold<int>(
              0,
              (sum, item) => sum + item.balancePaisa,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _DashboardHeader(
                  totalPaisa: total,
                  todayNetPaisa: todayNet.asData?.value ?? 0,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push(AppRoute.entry.path),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New entry'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.push(AppRoute.openingBalances.path),
                        icon: const Icon(Icons.flag_rounded),
                        label: const Text('Opening'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () =>
                            context.push('${AppRoute.entry.path}?kind=expense'),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Add expense'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(AppRoute.reports.path),
                        icon: const Icon(Icons.summarize_rounded),
                        label: const Text('Today report'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Business snapshot',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quick read of the last week, last months, and your running balance.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _WeeklySummaryCard(summary: weeklySummary),
                const SizedBox(height: 10),
                _MonthlyExpenseCard(summary: monthlyExpenses),
                const SizedBox(height: 10),
                _BalanceTrendCard(summary: balanceTrend),
                const SizedBox(height: 22),
                Text(
                  'Accounts',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const _EmptyDashboard()
                else
                  for (final item in visible.take(4))
                    _DashboardAccountTile(item: item),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => context.push(AppRoute.accounts.path),
                  child: const Text('View all accounts'),
                ),
                const SizedBox(height: 22),
                Text(
                  'Latest activity',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                activity.when(
                  loading: () => const _LoadingActivity(),
                  error: (error, stackTrace) => Text(error.toString()),
                  data: (items) => items.isEmpty
                      ? const _EmptyActivity()
                      : Column(
                          children: [
                            for (final item in items) _ActivityTile(item: item),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.isSyncing) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Tooltip(
      message: status.hasPendingWork
          ? '${status.unsyncedCount} changes pending sync'
          : 'Synced',
      child: Icon(
        status.hasPendingWork
            ? Icons.cloud_upload_rounded
            : Icons.cloud_done_rounded,
        color: status.hasPendingWork ? AppTheme.clay : AppTheme.leaf,
        size: 20,
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.totalPaisa,
    required this.todayNetPaisa,
  });

  final int totalPaisa;
  final int todayNetPaisa;

  @override
  Widget build(BuildContext context) {
    final netColor = todayNetPaisa >= 0
        ? const Color(0xFFA8D5BA)
        : const Color(0xFFFFC9B8);

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
              'Total in hand',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Money.fromPaisa(totalPaisa).format(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Track every payment as it happens so your day-end numbers stay accurate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today net change',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      Money.fromPaisa(todayNetPaisa).format(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: netColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardAccountTile extends StatelessWidget {
  const _DashboardAccountTile({required this.item});

  final AccountBalance item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.account.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                item.balance.format(),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final LedgerActivityItem item;

  @override
  Widget build(BuildContext context) {
    final amount = item.kind == 'transfer' ? 'Transfer' : item.amount.format();
    final isPositive = item.amountPaisa >= 0;
    final color = item.kind == 'transfer'
        ? AppTheme.leaf
        : isPositive
        ? AppTheme.leaf
        : AppTheme.clay;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_activityIcon(item.kind), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.note?.isNotEmpty == true
                          ? item.note!
                          : _activityLabel(item.kind),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.primaryAccountName ?? 'Ledger entry',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                amount,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard({required this.summary});

  final AsyncValue<List<WeeklySummaryPoint>> summary;

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      title: 'Weekly net summary',
      subtitle:
          'Green bars mean more money came in than went out for that day.',
      child: summary.when(
        loading: () => const _InsightLoading(),
        error: (error, stackTrace) => Text(error.toString()),
        data: (points) {
          final hasData = points.any((point) => point.netPaisa != 0);
          if (!hasData) {
            return const _InsightEmpty(
              message:
                  'No weekly movement yet. Add a few entries and this chart will come alive.',
            );
          }

          final weeklyNet = points.fold<int>(
            0,
            (sum, point) => sum + point.netPaisa,
          );
          final weeklyNetColor = weeklyNet >= 0 ? AppTheme.leaf : AppTheme.clay;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WeeklyNetChart(points: points),
              const SizedBox(height: 8),
              Text(
                '7-day net: ${Money.fromPaisa(weeklyNet).format()}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: weeklyNetColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthlyExpenseCard extends StatelessWidget {
  const _MonthlyExpenseCard({required this.summary});

  final AsyncValue<List<MonthlyExpensePoint>> summary;

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      title: 'Monthly expenses',
      subtitle: 'This helps you spot months where spending jumped.',
      child: summary.when(
        loading: () => const _InsightLoading(),
        error: (error, stackTrace) => Text(error.toString()),
        data: (points) {
          final hasExpenses = points.any((point) => point.expensePaisa > 0);
          if (!hasExpenses) {
            return const _InsightEmpty(
              message:
                  'No expense entries in recent months. As soon as you record expenses, this chart will show totals month by month.',
            );
          }

          final latest = points.last;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MonthlyExpenseChart(points: points),
              const SizedBox(height: 8),
              Text(
                'Latest month: ${Money.fromPaisa(latest.expensePaisa).format()}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.clay,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceTrendCard extends StatelessWidget {
  const _BalanceTrendCard({required this.summary});

  final AsyncValue<List<BalanceTrendPoint>> summary;

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      title: 'Account balance trend',
      subtitle:
          'Your running in-hand balance over the last two weeks (excluding owner equity and expense buckets).',
      child: summary.when(
        loading: () => const _InsightLoading(),
        error: (error, stackTrace) => Text(error.toString()),
        data: (points) {
          if (points.length < 2) {
            return const _InsightEmpty(
              message: 'Need more days of data to plot a trend.',
            );
          }

          final first = points.first.totalBalancePaisa;
          final last = points.last.totalBalancePaisa;
          final delta = last - first;
          final hasMovement = points.any(
            (point) => point.totalBalancePaisa != first,
          );
          if (!hasMovement && last == 0) {
            return const _InsightEmpty(
              message:
                  'No balance movement yet. Add entries on different days to unlock this trend chart.',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BalanceTrendChart(points: points),
              const SizedBox(height: 8),
              Text(
                '14-day change: ${Money.fromPaisa(delta).format()}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: delta >= 0 ? AppTheme.leaf : AppTheme.clay,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InsightLoading extends StatelessWidget {
  const _InsightLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 92,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _InsightEmpty extends StatelessWidget {
  const _InsightEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _WeeklyNetChart extends StatelessWidget {
  const _WeeklyNetChart({required this.points});

  final List<WeeklySummaryPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxAbs = points.fold<int>(
      1,
      (current, point) => math.max(current, point.netPaisa.abs()),
    );

    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          const Align(
            alignment: Alignment.center,
            child: Divider(height: 1, color: AppTheme.line),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final point in points)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: point.netPaisa > 0
                              ? Container(
                                  width: 12,
                                  height: 34 * (point.netPaisa / maxAbs),
                                  decoration: BoxDecoration(
                                    color: AppTheme.leaf,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: point.netPaisa < 0
                              ? Container(
                                  width: 12,
                                  height: 34 * (point.netPaisa.abs() / maxAbs),
                                  decoration: BoxDecoration(
                                    color: AppTheme.clay,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('E').format(point.businessDate).substring(
                          0,
                          2,
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.black54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyExpenseChart extends StatelessWidget {
  const _MonthlyExpenseChart({required this.points});

  final List<MonthlyExpensePoint> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<int>(
      1,
      (current, point) => math.max(current, point.expensePaisa),
    );

    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 14,
                        height: 58 * (point.expensePaisa / maxValue),
                        decoration: BoxDecoration(
                          color: AppTheme.clay.withValues(
                            alpha: point == points.last ? 1 : 0.72,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM').format(point.monthStart),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceTrendChart extends StatelessWidget {
  const _BalanceTrendChart({required this.points});

  final List<BalanceTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final values = points
        .map((point) => point.totalBalancePaisa.toDouble())
        .toList(growable: false);

    return SizedBox(
      height: 94,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _BalanceTrendPainter(values: values),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                DateFormat('d MMM').format(points.first.businessDate),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('d MMM').format(points.last.businessDate),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceTrendPainter extends CustomPainter {
  const _BalanceTrendPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueSpan = (maxValue - minValue).abs();
    final denominator = valueSpan == 0 ? 1 : valueSpan;
    final stepX = size.width / (values.length - 1);

    final linePath = Path();
    final fillPath = Path();
    for (var index = 0; index < values.length; index++) {
      final x = index * stepX;
      final normalized = (values[index] - minValue) / denominator;
      final y = size.height - (normalized * size.height);
      if (index == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = AppTheme.leaf.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = AppTheme.leaf
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    final lastY = size.height - ((values.last - minValue) / denominator) * size.height;
    canvas.drawCircle(
      Offset(size.width, lastY),
      3,
      Paint()..color = AppTheme.leaf,
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceTrendPainter oldDelegate) {
    if (oldDelegate.values.length != values.length) {
      return true;
    }
    for (var index = 0; index < values.length; index++) {
      if (oldDelegate.values[index] != values[index]) {
        return true;
      }
    }
    return false;
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Start by posting opening balances. After that, daily balances and charts will update automatically.',
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No activity yet. Tap New entry whenever money comes in, goes out, or moves between accounts.',
        ),
      ),
    );
  }
}

class _LoadingActivity extends StatelessWidget {
  const _LoadingActivity();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ActivityLoadingBlock(),
        SizedBox(height: 10),
        _ActivityLoadingBlock(),
      ],
    );
  }
}

class _ActivityLoadingBlock extends StatelessWidget {
  const _ActivityLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const SizedBox(height: 66),
    );
  }
}

IconData _activityIcon(String kind) {
  return switch (kind) {
    'cash_in' => Icons.south_west_rounded,
    'cash_out' => Icons.north_east_rounded,
    'transfer' => Icons.swap_horiz_rounded,
    'expense' => Icons.receipt_long_rounded,
    _ => Icons.tune_rounded,
  };
}

String _activityLabel(String kind) {
  return switch (kind) {
    'cash_in' => 'Cash in',
    'cash_out' => 'Cash out',
    'transfer' => 'Transfer',
    'expense' => 'Expense',
    _ => 'Adjustment',
  };
}
