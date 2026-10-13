import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_decimal.dart';

void main() {
  test('decimal arithmetic has no binary floating point drift', () {
    expect(
      (TaxDecimal.parse('0.1') + TaxDecimal.parse('0.2')).toString(),
      '0.3',
    );
    expect(
      TaxDecimal.parse('9007199254740993.125').toString(),
      '9007199254740993.125',
    );
    expect(TaxDecimal.parse('1.000'), TaxDecimal.one);
    expect(TaxDecimal.parse('1.000').hashCode, TaxDecimal.one.hashCode);
    expect(
      (TaxDecimal.parse('1.2') * TaxDecimal.parse('0.3')).toString(),
      '0.36',
    );
  });
  test('rounding is half away from zero', () {
    expect(TaxDecimal.parse('1.005').rounded().toString(), '1.01');
    expect(TaxDecimal.parse('-1.005').rounded().toString(), '-1.01');
    expect(TaxDecimal.one.divide(TaxDecimal.parse('3')).toString(), '0.33');
  });
  test('invalid and exponent decimals are rejected', () {
    for (final value in ['NaN', 'Infinity', '1e3', '1,000', ' 1', '']) {
      expect(() => TaxDecimal.parse(value), throwsFormatException);
    }
    expect(() => TaxDecimal.one.divide(TaxDecimal.zero), throwsArgumentError);
    expect(() => TaxDecimal.parse('0.1234567890123'), throwsFormatException);
    expect(() => TaxDecimal.parse('1' * 129), throwsFormatException);
    expect(
      () => TaxDecimal.one.divide(TaxDecimal.one, precision: -1),
      throwsArgumentError,
    );
    expect(
      () => TaxDecimal.one.divide(TaxDecimal.one, precision: 10000),
      throwsArgumentError,
    );
  });
}
