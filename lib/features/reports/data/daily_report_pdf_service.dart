import 'package:dukaan_book/core/money/money.dart';
import 'package:dukaan_book/core/time/business_date.dart';
import 'package:dukaan_book/features/reports/data/daily_report_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final dailyReportPdfServiceProvider = Provider<DailyReportPdfService>((ref) {
  return const DailyReportPdfService();
});

class DailyReportPdfService {
  const DailyReportPdfService();

  static Future<pw.ThemeData>? _themeFuture;

  Future<Uint8List> buildDailyReportPdf({
    required DailyReport report,
    required String shopName,
    DateTime? generatedAt,
    bool compress = true,
  }) async {
    final generated = generatedAt ?? DateTime.now().toUtc();
    final document = pw.Document(compress: compress);
    final theme = await _pdfTheme();

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
          theme: theme,
        ),
        build: (context) => [
          _buildHeader(
            shopName: shopName,
            report: report,
            generatedAt: generated,
          ),
          pw.SizedBox(height: 14),
          _buildTotals(report),
          pw.SizedBox(height: 12),
          _buildAccountBalances(report.accounts),
          pw.SizedBox(height: 12),
          _buildExpenseBreakdown(report.expensesByCategory),
          pw.SizedBox(height: 12),
          _buildSummaryFooter(report),
        ],
      ),
    );

    return document.save();
  }

  static Future<pw.ThemeData> _pdfTheme() {
    return _themeFuture ??= _loadPdfTheme();
  }

  static Future<pw.ThemeData> _loadPdfTheme() async {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
    );
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [arabic],
    );
  }

  String reportFileName({
    required String shopName,
    required DateTime businessDate,
  }) {
    final date = DateFormat('yyyyMMdd').format(businessDate);
    final normalized = shopName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final safeShopName = normalized.isEmpty ? 'shop' : normalized;
    return '${safeShopName}_day_end_$date.pdf';
  }

  pw.Widget _buildHeader({
    required String shopName,
    required DailyReport report,
    required DateTime generatedAt,
  }) {
    final dateLabel = DateFormat('EEE, d MMM yyyy').format(report.businessDate);
    final generatedLabel = DateFormat(
      'd MMM yyyy, h:mm a',
    ).format(generatedAt.toLocal());

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F2F8F5'),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromHex('#DCE7E0')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Day-end report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#17211B'),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            shopName,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#2F6B45'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Business date: $dateLabel'),
          pw.Text('Generated: $generatedLabel'),
          if (report.isClosed)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Status: Closed snapshot',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#0F766E'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildTotals(DailyReport report) {
    return _sectionCard(
      title: 'Movement totals',
      child: pw.Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _metricPill('Net change', _money(report.netChangePaisa)),
          _metricPill('Inflow', _money(report.inflowPaisa)),
          _metricPill('Outflow', _money(report.outflowPaisa)),
          _metricPill('Expenses', _money(report.expensePaisa)),
          _metricPill('Profit', _money(report.serviceChargePaisa)),
          _metricPill('Transfers', _money(report.transferPaisa)),
        ],
      ),
    );
  }

  pw.Widget _buildAccountBalances(List<DailyReportAccountBalance> accounts) {
    if (accounts.isEmpty) {
      return _sectionCard(
        title: 'Account balances',
        child: pw.Text('No account balances were available for this day.'),
      );
    }

    return _sectionCard(
      title: 'Account balances',
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE7E0')),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.6),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.4),
        },
        children: [
          _tableHeader(const ['Account', 'Opening', 'Movement', 'Closing']),
          for (final account in accounts)
            pw.TableRow(
              children: [
                _tableCell(account.accountName),
                _tableCell(_money(account.openingBalancePaisa)),
                _tableCell(_money(account.movementPaisa)),
                _tableCell(_money(account.closingBalancePaisa), isBold: true),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget _buildExpenseBreakdown(List<ExpenseCategoryTotal> items) {
    if (items.isEmpty) {
      return _sectionCard(
        title: 'Expense breakdown',
        child: pw.Text('No expenses recorded for this day.'),
      );
    }

    final total = items.fold<int>(0, (sum, item) => sum + item.amountPaisa);
    return _sectionCard(
      title: 'Expense breakdown',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Total expenses: ${_money(total)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromHex('#DCE7E0')),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.8),
              1: pw.FlexColumnWidth(1.2),
            },
            children: [
              _tableHeader(const ['Category', 'Amount']),
              for (final item in items)
                pw.TableRow(
                  children: [
                    _tableCell(item.categoryName),
                    _tableCell(_money(item.amountPaisa), isBold: true),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryFooter(DailyReport report) {
    final hasData =
        report.accounts.isNotEmpty ||
        report.transactions.isNotEmpty ||
        report.expensesByCategory.isNotEmpty;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAF9'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#DCE7E0')),
      ),
      child: pw.Text(
        hasData
            ? 'This export was generated from local day-end report values for ${BusinessDate.toIsoDate(report.businessDate)}.'
            : 'No-data day: no account balances, expenses, or transactions were available for this date.',
      ),
    );
  }

  pw.Widget _sectionCard({required String title, required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#DCE7E0')),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  pw.Widget _metricPill(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAF9'),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor.fromHex('#DCE7E0')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }

  pw.TableRow _tableHeader(List<String> labels) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F2F8F5')),
      children: [
        for (final label in labels)
          _tableCell(label, isBold: true, padding: const pw.EdgeInsets.all(6)),
      ],
    );
  }

  pw.Widget _tableCell(
    String text, {
    bool isBold = false,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(6),
  }) {
    return pw.Padding(
      padding: padding,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String _money(int paisa) => Money.fromPaisa(paisa).format();
}
