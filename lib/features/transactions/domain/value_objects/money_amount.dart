/// Importo monetario in EUR rappresentato in centesimi (nessun `double`).
///
/// Limiti allineati a `NUMERIC(14, 2)`: massimo `999999999999.99`.
class MoneyAmount implements Comparable<MoneyAmount> {
  const MoneyAmount._(this.cents);

  /// Centesimi interi (>= 1).
  final int cents;

  static const int maxCents = 99999999999999; // 999999999999.99 EUR

  /// Accetta input italiano (virgola) o con punto; max 2 decimali.
  ///
  /// Supporta separatore migliaia italiano (`1.234,56`) e forme semplici
  /// (`12.99`, `0,10`, `12,99`).
  static MoneyAmount parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Importo vuoto', raw);
    }

    if (RegExp(r'[eE]').hasMatch(trimmed)) {
      throw FormatException('Notazione scientifica non consentita', raw);
    }

    if (!RegExp(r'^[0-9.,]+$').hasMatch(trimmed)) {
      throw FormatException('Importo non numerico', raw);
    }

    final normalized = _normalizeDecimal(trimmed);
    final parts = normalized.split('.');
    if (parts.length > 2) {
      throw FormatException('Formato importo non valido', raw);
    }

    final whole = parts[0];
    final fraction = parts.length == 2 ? parts[1] : '';

    if (whole.isEmpty || !RegExp(r'^\d+$').hasMatch(whole)) {
      throw FormatException('Parte intera non valida', raw);
    }
    if (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) {
      throw FormatException('Parte decimale non valida', raw);
    }
    if (fraction.length > 2) {
      throw FormatException('Massimo due cifre decimali', raw);
    }

    final paddedFraction = fraction.padRight(2, '0');
    final centsValue = int.parse(whole) * 100 + int.parse(paddedFraction);

    if (centsValue <= 0) {
      throw FormatException("L'importo deve essere maggiore di zero", raw);
    }
    if (centsValue > maxCents) {
      throw FormatException('Importo superiore al massimo consentito', raw);
    }

    return MoneyAmount._(centsValue);
  }

  /// Da stringa decimale canonica già validata (es. risposta Supabase).
  factory MoneyAmount.fromCanonicalDecimal(String value) {
    return MoneyAmount.parse(value.replaceAll(',', '.'));
  }

  factory MoneyAmount.fromCents(int cents) {
    if (cents <= 0) {
      throw ArgumentError.value(cents, 'cents', 'deve essere > 0');
    }
    if (cents > maxCents) {
      throw ArgumentError.value(cents, 'cents', 'supera il massimo');
    }
    return MoneyAmount._(cents);
  }

  /// Serializzazione esatta verso Supabase (`NUMERIC`).
  String toCanonicalDecimal() {
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  /// Formattazione UI euro con virgola (es. `12,99`).
  String formatEuro() {
    final whole = cents ~/ 100;
    final fraction = (cents % 100).toString().padLeft(2, '0');
    final wholeGrouped = _groupThousands(whole);
    return '$wholeGrouped,$fraction';
  }

  static String _normalizeDecimal(String input) {
    final hasComma = input.contains(',');
    final hasDot = input.contains('.');

    if (hasComma && hasDot) {
      // Formato italiano: 1.234,56
      if (input.lastIndexOf(',') > input.lastIndexOf('.')) {
        return input.replaceAll('.', '').replaceAll(',', '.');
      }
      throw FormatException('Formato importo ambiguo', input);
    }

    if (hasComma) {
      return input.replaceAll(',', '.');
    }

    return input;
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
  int compareTo(MoneyAmount other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MoneyAmount && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'MoneyAmount(${toCanonicalDecimal()})';
}
