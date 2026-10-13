/// Exact base-ten arithmetic. Currency allocations round half away from zero.
class TaxDecimal implements Comparable<TaxDecimal> {
  final BigInt coefficient;
  final int scale;
  const TaxDecimal._(this.coefficient, this.scale);
  static final zero = TaxDecimal._(BigInt.zero, 0);
  static final one = TaxDecimal._(BigInt.one, 0);

  factory TaxDecimal.parse(String text) {
    if (text.length > 128 || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
      throw FormatException('Expected an exact decimal', text);
    }
    final parts = text.split('.');
    if (parts.length == 2 && parts[1].length > 12) {
      throw FormatException('Decimal precision exceeds 12 places', text);
    }
    return TaxDecimal._(
      BigInt.parse(parts.join()),
      parts.length == 2 ? parts[1].length : 0,
    );
  }
  static BigInt _pow(int exponent) => BigInt.from(10).pow(exponent);
  BigInt _at(int precision) => coefficient * _pow(precision - scale);
  TaxDecimal operator +(TaxDecimal other) {
    final precision = scale > other.scale ? scale : other.scale;
    return TaxDecimal._(_at(precision) + other._at(precision), precision);
  }

  TaxDecimal operator -(TaxDecimal other) =>
      this + TaxDecimal._(-other.coefficient, other.scale);
  TaxDecimal operator *(TaxDecimal other) =>
      TaxDecimal._(coefficient * other.coefficient, scale + other.scale);
  TaxDecimal divide(TaxDecimal divisor, {int precision = 2}) {
    if (precision < 0 || precision > 12) {
      throw ArgumentError.value(precision, 'precision', 'Expected 0 to 12');
    }
    if (divisor.coefficient == BigInt.zero) {
      throw ArgumentError('Division by zero');
    }
    final numerator = coefficient * _pow(divisor.scale + precision);
    final denominator = divisor.coefficient * _pow(scale);
    var result = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator);
    if (remainder.abs() * BigInt.two >= denominator.abs()) {
      result += numerator.sign * denominator.sign < 0
          ? -BigInt.one
          : BigInt.one;
    }
    return TaxDecimal._(result, precision);
  }

  TaxDecimal rounded([int precision = 2]) => divide(one, precision: precision);
  bool get isNegative => coefficient.isNegative;
  bool get isZero => coefficient == BigInt.zero;
  @override
  int compareTo(TaxDecimal other) {
    final precision = scale > other.scale ? scale : other.scale;
    return _at(precision).compareTo(other._at(precision));
  }

  bool operator <(TaxDecimal other) => compareTo(other) < 0;
  bool operator <=(TaxDecimal other) => compareTo(other) <= 0;
  bool operator >(TaxDecimal other) => compareTo(other) > 0;
  bool operator >=(TaxDecimal other) => compareTo(other) >= 0;
  @override
  bool operator ==(Object other) =>
      other is TaxDecimal && compareTo(other) == 0;
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() {
    var digits = coefficient.abs().toString().padLeft(scale + 1, '0');
    if (scale > 0) {
      digits =
          '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
      digits = digits
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '${coefficient.isNegative ? '-' : ''}$digits';
  }
}
