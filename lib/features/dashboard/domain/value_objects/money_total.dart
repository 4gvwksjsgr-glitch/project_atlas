/// Totale monetario EUR in centesimi non negativi (include zero). Nessun `double`.
///
/// Costruito solo da stringa decimale canonica (punto, max 2 decimali).
class MoneyTotal implements Comparable<MoneyTotal> {
  const MoneyTotal._(this.cents);

  /// Centesimi interi (>= 0).
  final int cents;

  static const int maxCents = 99999999999999; // 999999999999.99 EUR
  static const MoneyTotal zero = MoneyTotal._(0);

  /// Da stringa canonica tipo `0`, `0.00`, `12.5`, `12.50`.
  factory MoneyTotal.fromCanonicalDecimal(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Importo vuoto', raw);
    }
    if (RegExp(r'[eE]').hasMatch(trimmed)) {
      throw FormatException('Notazione scientifica non consentita', raw);
    }
    if (trimmed.contains(',')) {
      throw FormatException('Attesa forma canonica con punto', raw);
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(trimmed)) {
      throw FormatException('Importo non canonico', raw);
    }

    final parts = trimmed.split('.');
    final whole = parts[0];
    final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    final centsValue = int.parse(whole) * 100 + int.parse(fraction);

    if (centsValue < 0) {
      throw FormatException('Importo negativo non consentito', raw);
    }
    if (centsValue > maxCents) {
      throw FormatException('Importo superiore al massimo consentito', raw);
    }

    return MoneyTotal._(centsValue);
  }

  factory MoneyTotal.fromCents(int cents) {
    if (cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'deve essere >= 0');
    }
    if (cents > maxCents) {
      throw ArgumentError.value(cents, 'cents', 'supera il massimo');
    }
    return MoneyTotal._(cents);
  }

  String toCanonicalDecimal() {
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  /// Formattazione UI euro con virgola (es. `0,00`, `12,99`).
  String formatEuro() {
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '${_groupThousands(whole)},$fraction';
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
  int compareTo(MoneyTotal other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MoneyTotal && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'MoneyTotal(${toCanonicalDecimal()})';
}
