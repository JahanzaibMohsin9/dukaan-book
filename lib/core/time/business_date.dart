class BusinessDate {
  const BusinessDate._();

  static const Duration pakistanOffset = Duration(hours: 5);

  static DateTime today([DateTime? now]) {
    return fromInstant(now ?? DateTime.now().toUtc());
  }

  static DateTime fromInstant(DateTime instant) {
    final utc = instant.toUtc();
    final pakistanTime = utc.add(pakistanOffset);
    return DateTime(pakistanTime.year, pakistanTime.month, pakistanTime.day);
  }

  static String toIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
