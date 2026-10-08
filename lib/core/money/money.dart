import 'package:intl/intl.dart';

class Money implements Comparable<Money> {
  const Money.fromPaisa(this.paisa);

  factory Money.fromRupees(int rupees) {
    return Money.fromPaisa(rupees * paisaPerRupee);
  }

  static const int paisaPerRupee = 100;
  static final NumberFormat _formatter = NumberFormat.decimalPattern('en_PK');

  final int paisa;

  bool get isNegative => paisa < 0;
  bool get isZero => paisa == 0;

  Money operator +(Money other) => Money.fromPaisa(paisa + other.paisa);
  Money operator -(Money other) => Money.fromPaisa(paisa - other.paisa);
  Money operator -() => Money.fromPaisa(-paisa);

  String format({bool includeSymbol = true}) {
    final sign = isNegative ? '-' : '';
    final absolute = paisa.abs();
    final rupees = absolute ~/ paisaPerRupee;
    final paisaPart = absolute % paisaPerRupee;
    final amount = paisaPart == 0
        ? _formatter.format(rupees)
        : '${_formatter.format(rupees)}.${paisaPart.toString().padLeft(2, '0')}';

    return includeSymbol ? '${sign}PKR $amount' : '$sign$amount';
  }

  @override
  int compareTo(Money other) => paisa.compareTo(other.paisa);

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Money && other.paisa == paisa;
  }

  @override
  int get hashCode => paisa.hashCode;
}

class MoneyParser {
  const MoneyParser._();

  static Money parsePkr(String input) {
    final normalized = input
        .trim()
        .toUpperCase()
        .replaceAll('PKR', '')
        .replaceAll('RS.', '')
        .replaceAll('RS', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');

    if (normalized.isEmpty) {
      throw const FormatException('Amount is required.');
    }

    final isNegative = normalized.startsWith('-');
    final unsigned = isNegative ? normalized.substring(1) : normalized;
    final parts = unsigned.split('.');

    if (parts.length > 2 ||
        parts.first.isEmpty ||
        parts.any((part) => !RegExp(r'^\d*$').hasMatch(part))) {
      throw FormatException('Invalid PKR amount: $input');
    }

    final rupees = int.parse(parts.first);
    final paisaDigits = parts.length == 2 ? parts.last : '';
    if (paisaDigits.length > 2) {
      throw FormatException('PKR amount supports two paisa digits: $input');
    }

    final paisa = paisaDigits.isEmpty
        ? 0
        : int.parse(paisaDigits.padRight(2, '0'));
    final amount = (rupees * Money.paisaPerRupee) + paisa;

    return Money.fromPaisa(isNegative ? -amount : amount);
  }
}
