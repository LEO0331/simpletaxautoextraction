import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/foreign_currency_conversion.dart';

void main() {
  ForeignCurrencyConversion conversion(
    String rate,
    String date, {
    bool forex = true,
  }) => ForeignCurrencyConversion(
    currency: 'USD',
    foreignAmount: '100.01',
    audPerUnit: rate,
    date: date,
    evidenceReference: 'Synthetic dated rate',
    reviewed: true,
    separateForexReviewed: forex,
  );
  test('Distinct acquisition and disposal rates retain exact AUD cents', () {
    expect(conversion('1.5', '2023-01-01').audAmount.toString(), '150.02');
    expect(conversion('1.6', '2024-01-01').audAmount.toString(), '160.02');
  });
  test(
    'Unreviewed separate forex consequences prevent approved AUD result',
    () {
      expect(conversion('1.5', '2023-01-01', forex: false).audAmount, isNull);
      expect(conversion('0', '2023-01-01').audAmount, isNull);
      expect(conversion('1.5', '2023-02-30').audAmount, isNull);
    },
  );
}
