enum LedgerPostingKind {
  cashIn('cash_in'),
  cashOut('cash_out'),
  transfer('transfer'),
  expense('expense'),
  adjustment('adjustment');

  const LedgerPostingKind(this.value);

  final String value;

  static LedgerPostingKind fromValue(String value) {
    return LedgerPostingKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => throw ArgumentError('Unknown ledger kind: $value'),
    );
  }
}

class LedgerLineDraft {
  const LedgerLineDraft({
    required this.accountId,
    required this.amountPaisa,
    this.memo,
  });

  final String accountId;
  final int amountPaisa;
  final String? memo;
}

class LedgerPostingDraft {
  const LedgerPostingDraft({
    required this.kind,
    required this.amountPaisa,
    this.serviceChargePaisa = 0,
    this.accountId,
    this.fromAccountId,
    this.toAccountId,
    this.paymentAccountId,
    this.expenseAccountId,
  });

  final LedgerPostingKind kind;
  final int amountPaisa;
  final int serviceChargePaisa;
  final String? accountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String? paymentAccountId;
  final String? expenseAccountId;
}

class LedgerPostingEngine {
  const LedgerPostingEngine();

  List<LedgerLineDraft> buildLines(LedgerPostingDraft draft) {
    _requireNonZero(draft.amountPaisa);
    _requireNonNegative(draft.serviceChargePaisa);
    final amount = draft.amountPaisa.abs();

    return switch (draft.kind) {
      LedgerPostingKind.cashIn => [
        LedgerLineDraft(
          accountId: _require(draft.accountId, 'Cash-in account is required.'),
          amountPaisa: amount,
          memo: 'Cash in',
        ),
      ],
      LedgerPostingKind.cashOut => [
        LedgerLineDraft(
          accountId: _require(draft.accountId, 'Cash-out account is required.'),
          amountPaisa: -amount,
          memo: 'Cash out',
        ),
      ],
      LedgerPostingKind.transfer => _transferLines(
        draft,
        amount,
        draft.serviceChargePaisa,
      ),
      LedgerPostingKind.expense => [
        LedgerLineDraft(
          accountId: _require(
            draft.paymentAccountId,
            'Payment account is required.',
          ),
          amountPaisa: -amount,
          memo: 'Expense paid',
        ),
        LedgerLineDraft(
          accountId: _require(
            draft.expenseAccountId,
            'Expense category is required.',
          ),
          amountPaisa: amount,
          memo: 'Expense bucket',
        ),
      ],
      LedgerPostingKind.adjustment => [
        LedgerLineDraft(
          accountId: _require(
            draft.accountId,
            'Adjustment account is required.',
          ),
          amountPaisa: draft.amountPaisa,
          memo: 'Adjustment',
        ),
      ],
    };
  }

  List<LedgerLineDraft> _transferLines(
    LedgerPostingDraft draft,
    int amount,
    int serviceCharge,
  ) {
    final fromAccountId = _require(
      draft.fromAccountId,
      'From account is required.',
    );
    final toAccountId = _require(draft.toAccountId, 'To account is required.');
    if (fromAccountId == toAccountId) {
      throw const LedgerPostingValidationException(
        'Choose two different accounts.',
      );
    }

    return [
      LedgerLineDraft(
        accountId: fromAccountId,
        amountPaisa: -amount,
        memo: 'Transfer out',
      ),
      LedgerLineDraft(
        accountId: toAccountId,
        amountPaisa: amount + serviceCharge,
        memo: serviceCharge > 0
            ? 'Transfer in + service charge'
            : 'Transfer in',
      ),
    ];
  }

  static String _require(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      throw LedgerPostingValidationException(message);
    }
    return value;
  }

  static void _requireNonZero(int amountPaisa) {
    if (amountPaisa == 0) {
      throw const LedgerPostingValidationException('Amount must be non-zero.');
    }
  }

  static void _requireNonNegative(int amountPaisa) {
    if (amountPaisa < 0) {
      throw const LedgerPostingValidationException(
        'Service charge cannot be negative.',
      );
    }
  }
}

class LedgerPostingValidationException implements Exception {
  const LedgerPostingValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
