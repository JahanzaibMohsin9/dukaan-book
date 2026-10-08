import 'package:dukaan_book/features/reports/data/daily_report_pdf_service.dart';
import 'package:dukaan_book/features/reports/data/daily_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = DailyReportPdfService();

  test('builds a PDF report with expected header details', () async {
    final report = DailyReport(
      businessDate: DateTime(2026, 4, 13),
      isClosed: false,
      closedAt: null,
      accounts: [
        DailyReportAccountBalance(
          accountId: 'cash',
          accountName: 'Cash',
          accountType: 'cash',
          isActive: true,
          openingBalancePaisa: 100000,
          closingBalancePaisa: 125000,
        ),
      ],
      transactions: [
        DailyReportTransactionItem(
          id: 'tx-1',
          kind: 'cash_in',
          businessDate: DateTime(2026, 4, 13),
          createdAt: DateTime.utc(2026, 4, 13, 10),
          amountPaisa: 25000,
          lineCount: 1,
        ),
      ],
      inflowPaisa: 25000,
      outflowPaisa: 0,
      expensePaisa: 0,
      transferPaisa: 0,
      serviceChargePaisa: 0,
      netChangePaisa: 25000,
      expensesByCategory: const [],
      hasUnsyncedEntries: false,
    );

    final bytes = await service.buildDailyReportPdf(
      report: report,
      shopName: 'Demo Shop',
      generatedAt: DateTime.utc(2026, 4, 13, 18),
      compress: false,
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
    expect(
      service.reportFileName(
        shopName: 'Demo Shop',
        businessDate: DateTime(2026, 4, 13),
      ),
      'demo_shop_day_end_20260413.pdf',
    );
  });

  test('handles a no-data day in PDF export gracefully', () async {
    final report = DailyReport.empty(DateTime(2026, 4, 14));

    final bytes = await service.buildDailyReportPdf(
      report: report,
      shopName: 'No Data Store',
      generatedAt: DateTime.utc(2026, 4, 14, 7, 30),
      compress: false,
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('builds PDF with Unicode report text without crashing', () async {
    final report = DailyReport(
      businessDate: DateTime(2026, 4, 15),
      isClosed: false,
      closedAt: null,
      accounts: [
        DailyReportAccountBalance(
          accountId: 'cash',
          accountName: 'کیش',
          accountType: 'cash',
          isActive: true,
          openingBalancePaisa: 0,
          closingBalancePaisa: 125000,
        ),
      ],
      transactions: const [],
      inflowPaisa: 0,
      outflowPaisa: 0,
      expensePaisa: 125000,
      transferPaisa: 0,
      serviceChargePaisa: 0,
      netChangePaisa: -125000,
      expensesByCategory: const [
        ExpenseCategoryTotal(categoryName: 'کرایہ', amountPaisa: 125000),
      ],
      hasUnsyncedEntries: false,
    );

    final bytes = await service.buildDailyReportPdf(
      report: report,
      shopName: 'دکان',
      generatedAt: DateTime.utc(2026, 4, 15, 7, 30),
      compress: false,
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
