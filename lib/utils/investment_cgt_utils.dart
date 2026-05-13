double parseMoney(String input) {
  final cleaned = input
      .replaceAll(',', '')
      .replaceAll(r'$', '')
      .replaceAll('AUD', '')
      .replaceAll('aud', '')
      .trim();
  return double.tryParse(cleaned) ?? 0;
}

DateTime? parseFlexibleDate(String input) {
  final value = input.trim();
  if (value.isEmpty) {
    return null;
  }

  final slash = RegExp(r'^(\d{1,4})/(\d{1,2})/(\d{1,4})$');
  final dash = RegExp(r'^(\d{1,4})-(\d{1,2})-(\d{1,4})$');

  Match? m = slash.firstMatch(value);
  if (m != null) {
    return _buildDateFromParts(m.group(1)!, m.group(2)!, m.group(3)!);
  }
  m = dash.firstMatch(value);
  if (m != null) {
    return _buildDateFromParts(m.group(1)!, m.group(2)!, m.group(3)!);
  }
  return null;
}

DateTime? _buildDateFromParts(String a, String b, String c) {
  final p1 = int.tryParse(a);
  final p2 = int.tryParse(b);
  final p3 = int.tryParse(c);
  if (p1 == null || p2 == null || p3 == null) {
    return null;
  }

  // DD/MM/YYYY
  if (a.length <= 2 && c.length == 4) {
    return DateTime(p3, p2, p1);
  }
  // YYYY/MM/DD
  if (a.length == 4 && c.length <= 2) {
    return DateTime(p1, p2, p3);
  }
  // fallback
  if (p1 > 31) {
    return DateTime(p1, p2, p3);
  }
  return DateTime(p3, p2, p1);
}

int calculateHoldingDays(DateTime tradeDate, DateTime cutOffDate) {
  return cutOffDate.difference(tradeDate).inDays;
}

double calculateMarketValue(double units, double cutOffPrice) {
  return units * cutOffPrice;
}

double calculateGainLoss(double marketValue, double costBase) {
  return marketValue - costBase;
}

double calculateGainLossPercent(double gainLoss, double costBase) {
  if (costBase == 0) {
    return 0;
  }
  return (gainLoss / costBase) * 100;
}

bool isPotentialCgtDiscountEligible(int holdingDays) {
  return holdingDays > 365;
}

double calculateEstimatedTaxableGainAfterDiscount(
  double gainLoss,
  bool eligible,
) {
  if (gainLoss <= 0) {
    return 0;
  }
  return eligible ? gainLoss * 0.5 : gainLoss;
}
