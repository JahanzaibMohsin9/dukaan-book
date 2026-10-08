import 'package:dukaan_book/app/theme/app_theme.dart';
import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/core/time/business_date.dart';
import 'package:dukaan_book/features/auth/data/auth_repository.dart';
import 'package:dukaan_book/features/reports/data/daily_report_pdf_service.dart';
import 'package:dukaan_book/features/reports/data/daily_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

enum _ReportPdfAction { open, share }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _selectedDate;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = BusinessDate.today();
  }

  void _moveDay(int offset) {
    final today = BusinessDate.today();
    final target = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + offset,
    );
    final next = target.isAfter(today) ? today : target;
    setState(() {
      _selectedDate = DateTime(next.year, next.month, next.day);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: BusinessDate.today(),
      helpText: 'Select business date',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _openTransactionDetails(
    DailyReportTransactionItem transaction,
  ) async {
    final repository = ref.read(dailyReportRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TransactionDrillDownSheet(
        transaction: transaction,
        linesFuture: repository.getTransactionLines(
          transactionId: transaction.id,
        ),
      ),
    );
  }

  Future<void> _closeDay(DailyReport report) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this day?'),
        content: Text(
          'A snapshot for ${BusinessDate.toIsoDate(report.businessDate)} will be saved. '
          'Use reopen if you need to post corrections later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close day'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      return;
    }

    try {
      await ref
          .read(dailyReportRepositoryProvider)
          .closeDay(userId: userId, businessDate: report.businessDate);
      if (!mounted) {
        return;
      }
      ref.invalidate(dailyReportByDateProvider(_selectedDate));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day closed and snapshot saved.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reopenDay(DailyReport report) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen closed day?'),
        content: const Text(
          'Reopening allows posting corrections, which may change closed totals. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      return;
    }

    try {
      await ref
          .read(dailyReportRepositoryProvider)
          .reopenDay(userId: userId, businessDate: report.businessDate);
      if (!mounted) {
        return;
      }
      ref.invalidate(dailyReportByDateProvider(_selectedDate));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Day reopened. You can post corrections now.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _handlePdfAction(
    DailyReport report,
    _ReportPdfAction action,
  ) async {
    if (_isExportingPdf) {
      return;
    }

    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to export reports.')),
      );
      return;
    }

    setState(() {
      _isExportingPdf = true;
    });

    try {
      final repository = ref.read(dailyReportRepositoryProvider);
      final pdfService = ref.read(dailyReportPdfServiceProvider);
      final shopName =
          await repository.getActiveShopName(userId: userId) ?? 'My Shop';
      final bytes = await pdfService.buildDailyReportPdf(
        report: report,
        shopName: shopName,
      );
      final filename = pdfService.reportFileName(
        shopName: shopName,
        businessDate: report.businessDate,
      );

      if (action == _ReportPdfAction.share) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
      }

      if (!mounted) {
        return;
      }
      final message = action == _ReportPdfAction.share
          ? 'PDF sent to share sheet.'
          : 'PDF opened successfully.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(dailyReportByDateProvider(_selectedDate));
    final canGoForward = !_selectedDate.isAtSameMomentAs(BusinessDate.today());
    final reportValue = report.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day-end report'),
        actions: [
          PopupMenuButton<_ReportPdfAction>(
            tooltip: 'Export or share PDF',
            enabled: reportValue != null && !_isExportingPdf,
            onSelected: (action) {
              final value = report.asData?.value;
              if (value == null) {
                return;
              }
              _handlePdfAction(value, action);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ReportPdfAction.open,
                child: Text('Open PDF'),
              ),
              PopupMenuItem(
                value: _ReportPdfAction.share,
                child: Text('Share PDF'),
              ),
            ],
            icon: _isExportingPdf
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _DateSelectorCard(
              selectedDate: _selectedDate,
              canGoForward: canGoForward,
              onPrevious: () => _moveDay(-1),
              onNext: canGoForward ? () => _moveDay(1) : null,
              onPickDate: _pickDate,
            ),
            const SizedBox(height: 14),
            report.when(
              loading: () => const _ReportLoadingState(),
              error: (error, stackTrace) =>
                  _ErrorState(message: error.toString()),
              data: (value) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ClosingCard(
                      report: value,
                      onClose: () => _closeDay(value),
                      onReopen: () => _reopenDay(value),
                    ),
                    const SizedBox(height: 12),
                    if (value.hasUnsyncedEntries) const _UnsyncedWarning(),
                    if (value.hasUnsyncedEntries) const SizedBox(height: 12),
                    _MovementTotalsCard(report: value),
                    const SizedBox(height: 16),
                    const _SectionTitle(text: 'Account balances'),
                    const SizedBox(height: 10),
                    _AccountBalanceSection(accounts: value.accounts),
                    const SizedBox(height: 16),
                    const _SectionTitle(text: 'Expense breakdown'),
                    const SizedBox(height: 10),
                    _ExpenseBreakdownSection(
                      businessDate: value.businessDate,
                      items: value.expensesByCategory,
                    ),
                    const SizedBox(height: 16),
                    const _SectionTitle(text: 'Transactions'),
                    const SizedBox(height: 10),
                    _TransactionSection(
                      items: value.transactions,
                      onTap: _openTransactionDetails,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({
    required this.report,
    required this.onClose,
    required this.onReopen,
  });

  final DailyReport report;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final statusText = report.isClosed
        ? 'Closed at ${DateFormat('d MMM, h:mm a').format((report.closedAt ?? DateTime.now()).toLocal())}'
        : 'Open day';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: report.isClosed ? const Color(0xFF0F766E) : AppTheme.line,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily closing',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: report.isClosed
                          ? const Color(0xFF0F766E)
                          : Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            report.isClosed
                ? FilledButton.tonal(
                    onPressed: onReopen,
                    child: const Text('Reopen'),
                  )
                : FilledButton(
                    onPressed: onClose,
                    child: const Text('Close day'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _DateSelectorCard extends StatelessWidget {
  const _DateSelectorCard({
    required this.selectedDate,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
  });

  final DateTime selectedDate;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Business date',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: Colors.white,
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: onPickDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      DateFormat('EEE, d MMM yyyy').format(selectedDate),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: canGoForward ? Colors.white : Colors.white24,
                  tooltip: 'Next day',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementTotalsCard extends StatelessWidget {
  const _MovementTotalsCard({required this.report});

  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movement totals',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricPill(
                  label: 'Net',
                  value: Money.fromPaisa(report.netChangePaisa).format(),
                  valueColor: report.netChangePaisa >= 0
                      ? AppTheme.leaf
                      : AppTheme.clay,
                ),
                _MetricPill(
                  label: 'Inflow',
                  value: Money.fromPaisa(report.inflowPaisa).format(),
                  valueColor: AppTheme.leaf,
                ),
                _MetricPill(
                  label: 'Outflow',
                  value: Money.fromPaisa(report.outflowPaisa).format(),
                  valueColor: AppTheme.clay,
                ),
                _MetricPill(
                  label: 'Expenses',
                  value: Money.fromPaisa(report.expensePaisa).format(),
                  valueColor: AppTheme.clay,
                ),
                _MetricPill(
                  label: 'Profit',
                  value: Money.fromPaisa(report.serviceChargePaisa).format(),
                  valueColor: AppTheme.leaf,
                ),
                _MetricPill(
                  label: 'Transfers',
                  value: Money.fromPaisa(report.transferPaisa).format(),
                  valueColor: AppTheme.ink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mint,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountBalanceSection extends StatelessWidget {
  const _AccountBalanceSection({required this.accounts});

  final List<DailyReportAccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const _EmptyCard(
        message: 'No account data is available for this day.',
      );
    }

    return Column(
      children: [
        for (final account in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.accountName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Money.fromPaisa(account.closingBalancePaisa).format(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Opening: ${Money.fromPaisa(account.openingBalancePaisa).format()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Move: ${Money.fromPaisa(account.movementPaisa).format()}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: account.movementPaisa >= 0
                                    ? AppTheme.leaf
                                    : AppTheme.clay,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpenseBreakdownSection extends StatelessWidget {
  const _ExpenseBreakdownSection({
    required this.businessDate,
    required this.items,
  });

  final DateTime businessDate;
  final List<ExpenseCategoryTotal> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyCard(
        message:
            'No expenses recorded for ${BusinessDate.toIsoDate(businessDate)}.',
      );
    }

    final total = items.fold<int>(0, (sum, item) => sum + item.amountPaisa);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total: ${Money.fromPaisa(total).format()}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.categoryName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      Money.fromPaisa(item.amountPaisa).format(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.clay,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransactionSection extends StatelessWidget {
  const _TransactionSection({required this.items, required this.onTap});

  final List<DailyReportTransactionItem> items;
  final ValueChanged<DailyReportTransactionItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyCard(message: 'No transactions posted for this day.');
    }

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onTap(item),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _kindColor(item.kind).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _kindIcon(item.kind),
                          size: 18,
                          color: _kindColor(item.kind),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kindLabel(item.kind),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _transactionSubtitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.kind == 'transfer'
                                ? 'Transfer'
                                : Money.fromPaisa(item.amountPaisa).format(),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: _amountColor(item),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.lineCount} lines',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black45),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black38,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _transactionSubtitle(DailyReportTransactionItem item) {
    final time = DateFormat('h:mm a').format(item.createdAt.toLocal());
    final first = item.primaryAccountName ?? 'No account';
    final note = item.note?.trim();
    if (note == null || note.isEmpty) {
      return '$first - $time';
    }
    return '$first - $time - $note';
  }

  static Color _amountColor(DailyReportTransactionItem item) {
    if (item.kind == 'transfer') {
      return AppTheme.ink;
    }
    return item.amountPaisa >= 0 ? AppTheme.leaf : AppTheme.clay;
  }

  static String _kindLabel(String kind) {
    switch (kind) {
      case 'cash_in':
        return 'Cash in';
      case 'cash_out':
        return 'Cash out';
      case 'expense':
        return 'Expense';
      case 'transfer':
        return 'Transfer';
      case 'adjustment':
        return 'Adjustment';
      default:
        return kind;
    }
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'cash_in':
        return Icons.south_west_rounded;
      case 'cash_out':
        return Icons.north_east_rounded;
      case 'expense':
        return Icons.receipt_long_rounded;
      case 'transfer':
        return Icons.swap_horiz_rounded;
      case 'adjustment':
        return Icons.tune_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  static Color _kindColor(String kind) {
    switch (kind) {
      case 'cash_in':
        return AppTheme.leaf;
      case 'cash_out':
      case 'expense':
        return AppTheme.clay;
      case 'transfer':
        return AppTheme.ink;
      case 'adjustment':
        return const Color(0xFF0F766E);
      default:
        return AppTheme.ink;
    }
  }
}

class _TransactionDrillDownSheet extends StatelessWidget {
  const _TransactionDrillDownSheet({
    required this.transaction,
    required this.linesFuture,
  });

  final DailyReportTransactionItem transaction;
  final Future<List<DailyReportTransactionLine>> linesFuture;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaction details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat(
                      'h:mm a',
                    ).format(transaction.createdAt.toLocal()),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<DailyReportTransactionLine>>(
                future: linesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }

                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const _EmptyCard(
                      message:
                          'No ledger lines were found for this transaction.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final line = items[index];
                      final isPositive = line.amountPaisa >= 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppTheme.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.accountName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      if ((line.memo ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          line.memo!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.black54),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  Money.fromPaisa(line.amountPaisa).format(),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: isPositive
                                            ? AppTheme.leaf
                                            : AppTheme.clay,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _ReportLoadingState extends StatelessWidget {
  const _ReportLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _EmptyCard(message: message);
  }
}

class _UnsyncedWarning extends StatelessWidget {
  const _UnsyncedWarning();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2E8),
        border: Border.all(color: const Color(0xFFD86F45)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Unsynced local entries are present. This report reflects local data and may differ from remote until sync completes.',
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: Text(message)),
    );
  }
}
