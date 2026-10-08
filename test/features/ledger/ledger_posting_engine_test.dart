import 'package:dukaan_book/features/ledger/domain/ledger_posting_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = LedgerPostingEngine();

  test('cash in creates one positive line', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.cashIn,
        amountPaisa: 12500,
        accountId: 'cash',
      ),
    );

    expect(lines, hasLength(1));
    expect(lines.single.accountId, 'cash');
    expect(lines.single.amountPaisa, 12500);
  });

  test('cash out creates one negative line', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.cashOut,
        amountPaisa: 12500,
        accountId: 'cash',
      ),
    );

    expect(lines.single.amountPaisa, -12500);
  });

  test('transfer creates deterministic negative then positive lines', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.transfer,
        amountPaisa: 5000,
        fromAccountId: 'cash',
        toAccountId: 'bank',
      ),
    );

    expect(lines.map((line) => line.accountId), ['cash', 'bank']);
    expect(lines.map((line) => line.amountPaisa), [-5000, 5000]);
  });

  test('transfer service charge is added to receiving account as profit', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.transfer,
        amountPaisa: 100000,
        serviceChargePaisa: 1000,
        fromAccountId: 'cash',
        toAccountId: 'easypaisa',
      ),
    );

    expect(lines, hasLength(2));
    expect(lines[0].accountId, 'cash');
    expect(lines[0].amountPaisa, -100000);
    expect(lines[1].accountId, 'easypaisa');
    expect(lines[1].amountPaisa, 101000);
    expect(lines.fold<int>(0, (sum, line) => sum + line.amountPaisa), 1000);
  });

  test('expense reduces payment account and increases expense bucket', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.expense,
        amountPaisa: 7000,
        paymentAccountId: 'cash',
        expenseAccountId: 'rent',
      ),
    );

    expect(lines.map((line) => line.accountId), ['cash', 'rent']);
    expect(lines.map((line) => line.amountPaisa), [-7000, 7000]);
  });

  test('adjustment preserves the signed amount', () {
    final lines = engine.buildLines(
      const LedgerPostingDraft(
        kind: LedgerPostingKind.adjustment,
        amountPaisa: -3000,
        accountId: 'cash',
      ),
    );

    expect(lines.single.amountPaisa, -3000);
  });

  test('invalid input cases throw validation errors', () {
    expect(
      () => engine.buildLines(
        const LedgerPostingDraft(
          kind: LedgerPostingKind.cashIn,
          amountPaisa: 0,
          accountId: 'cash',
        ),
      ),
      throwsA(isA<LedgerPostingValidationException>()),
    );
    expect(
      () => engine.buildLines(
        const LedgerPostingDraft(
          kind: LedgerPostingKind.transfer,
          amountPaisa: 100,
          fromAccountId: 'cash',
          toAccountId: 'cash',
        ),
      ),
      throwsA(isA<LedgerPostingValidationException>()),
    );
    expect(
      () => engine.buildLines(
        const LedgerPostingDraft(
          kind: LedgerPostingKind.transfer,
          amountPaisa: 100000,
          serviceChargePaisa: -1000,
          fromAccountId: 'cash',
          toAccountId: 'easypaisa',
        ),
      ),
      throwsA(isA<LedgerPostingValidationException>()),
    );
    expect(
      () => engine.buildLines(
        const LedgerPostingDraft(
          kind: LedgerPostingKind.expense,
          amountPaisa: 100,
          paymentAccountId: 'cash',
        ),
      ),
      throwsA(isA<LedgerPostingValidationException>()),
    );
  });
}
