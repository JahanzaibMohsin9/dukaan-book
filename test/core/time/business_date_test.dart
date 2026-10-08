import 'package:dukaan_book/core/time/business_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessDate', () {
    test('converts UTC instant to Pakistan local date', () {
      final beforeMidnightUtc = DateTime.utc(2026, 4, 12, 20);
      final businessDate = BusinessDate.fromInstant(beforeMidnightUtc);

      expect(BusinessDate.toIsoDate(businessDate), '2026-04-13');
    });

    test('keeps same date before Pakistan midnight', () {
      final eveningUtc = DateTime.utc(2026, 4, 13, 18, 59);
      final businessDate = BusinessDate.fromInstant(eveningUtc);

      expect(BusinessDate.toIsoDate(businessDate), '2026-04-13');
    });
  });
}
