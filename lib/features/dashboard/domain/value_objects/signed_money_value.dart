import 'money_total.dart';

/// Saldo monetario in centesimi con segno (positivo, zero o negativo).
class SignedMoneyValue {
  const SignedMoneyValue._(this.cents);

  /// Centesimi con segno.
  final int cents;

  factory SignedMoneyValue.fromDifference({
    required MoneyTotal income,
    required MoneyTotal expense,
  }) {
    return SignedMoneyValue._(income.cents - expense.cents);
  }

  factory SignedMoneyValue.fromCents(int cents) => SignedMoneyValue._(cents);

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  /// Es. `+12,99 €`, `0,00 €`, `−25,50 €` (meno Unicode).
  String formatEuroSigned() {
    final absCents = cents.abs();
    final whole = absCents ~/ 100;
    final fraction = (absCents % 100).toString().padLeft(2, '0');
    final grouped = _groupThousands(whole);
    final amount = '$grouped,$fraction';

    if (cents > 0) {
      return '+$amount €';
    }
    if (cents < 0) {
      return '−$amount €';
    }
    return '$amount €';
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignedMoneyValue && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'SignedMoneyValue($cents)';
}
