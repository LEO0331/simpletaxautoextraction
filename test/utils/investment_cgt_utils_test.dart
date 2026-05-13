import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/utils/investment_cgt_utils.dart';

void main() {
  group('investment cgt utils', () {
    test('parseMoney handles currency format', () {
      expect(parseMoney(r'$3,980.74'), closeTo(3980.74, 0.0001));
      expect(parseMoney('AUD 7.94'), closeTo(7.94, 0.0001));
    });

    test('parseFlexibleDate handles multiple formats', () {
      expect(parseFlexibleDate('30/03/2026'), DateTime(2026, 3, 30));
      expect(parseFlexibleDate('2026-03-30'), DateTime(2026, 3, 30));
      expect(parseFlexibleDate('2026/03/30'), DateTime(2026, 3, 30));
    });

    test('holding and gain calculations', () {
      final days = calculateHoldingDays(
        DateTime(2025, 2, 10),
        DateTime(2026, 3, 10),
      );
      expect(days, greaterThan(365));
      final marketValue = calculateMarketValue(80, 75);
      expect(marketValue, 6000);
      final gain = calculateGainLoss(marketValue, 5000);
      expect(gain, 1000);
      expect(calculateGainLossPercent(gain, 5000), closeTo(20, 0.0001));
      expect(isPotentialCgtDiscountEligible(days), isTrue);
      expect(
        calculateEstimatedTaxableGainAfterDiscount(gain, true),
        closeTo(500, 0.0001),
      );
      expect(calculateEstimatedTaxableGainAfterDiscount(-1, true), 0);
    });
  });
}
