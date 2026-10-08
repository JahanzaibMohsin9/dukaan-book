import 'package:dukaan_book/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('formats positive, negative, zero, and paisa values', () {
      expect(const Money.fromPaisa(1250000).format(), 'PKR 12,500');
      expect(const Money.fromPaisa(-1250000).format(), '-PKR 12,500');
      expect(const Money.fromPaisa(0).format(), 'PKR 0');
      expect(const Money.fromPaisa(10050).format(), 'PKR 100.50');
    });

    test('parses PKR input into integer paisa', () {
      expect(MoneyParser.parsePkr('PKR 12,500').paisa, 1250000);
      expect(MoneyParser.parsePkr('Rs. 100.5').paisa, 10050);
      expect(MoneyParser.parsePkr('-50').paisa, -5000);
      expect(MoneyParser.parsePkr('0').paisa, 0);
    });

    test('rejects malformed amounts', () {
      expect(() => MoneyParser.parsePkr(''), throwsFormatException);
      expect(() => MoneyParser.parsePkr('12.345'), throwsFormatException);
      expect(() => MoneyParser.parsePkr('abc'), throwsFormatException);
    });
  });
}
