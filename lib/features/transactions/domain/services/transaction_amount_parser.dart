import '../value_objects/transaction_import_formats.dart';

/// Esito della lettura di una cella importo.
sealed class AmountParseOutcome {
  const AmountParseOutcome();
}

/// Importo interpretato senza ambiguità. [cents] è sempre il valore assoluto.
final class AmountParsed extends AmountParseOutcome {
  const AmountParsed({required this.cents, required this.isNegative});

  final int cents;
  final bool isNegative;

  bool get isZero => cents == 0;

  @override
  String toString() =>
      'AmountParsed(cents: $cents, isNegative: $isNegative)';
}

/// Separatori interpretabili in due modi: serve una scelta esplicita.
final class AmountAmbiguous extends AmountParseOutcome {
  const AmountAmbiguous();

  @override
  String toString() => 'AmountAmbiguous()';
}

/// Cella non interpretabile. [code] è un codice localizzabile senza dati.
final class AmountInvalid extends AmountParseOutcome {
  const AmountInvalid(this.code);

  final String code;

  @override
  String toString() => 'AmountInvalid($code)';
}

/// Legge importi in formato italiano o anglosassone senza mai indovinare.
///
/// Accetta `1234.56`, `1,234.56`, `1234,56`, `1.234,56`, `-123,45`, `(123,45)`.
/// Quando un unico separatore con tre cifre a destra può essere sia migliaia
/// sia decimale (es. `1.234`) l'esito è [AmountAmbiguous] finché l'utente non
/// sceglie un [NumberFormatPreference].
abstract final class TransactionAmountParser {
  static const int maxCents = 99999999999999;

  static AmountParseOutcome parse(
    String raw, {
    NumberFormatPreference preference = NumberFormatPreference.auto,
  }) {
    var text = raw.trim();
    if (text.isEmpty) {
      return const AmountInvalid('amountMissing');
    }

    text = text
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll('€', '')
        .replaceAll(RegExp('eur', caseSensitive: false), '')
        .replaceAll(' ', '')
        .replaceAll("'", '');

    var isNegative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      isNegative = true;
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.startsWith('-') || text.startsWith('\u2212')) {
      isNegative = !isNegative;
      text = text.substring(1).trim();
    } else if (text.startsWith('+')) {
      text = text.substring(1).trim();
    }

    if (text.isEmpty) {
      return const AmountInvalid('amountMissing');
    }
    if (!RegExp(r'^[0-9.,]+$').hasMatch(text)) {
      return const AmountInvalid('amountNotNumeric');
    }

    final resolved = _splitIntoWholeAndFraction(text, preference);
    if (resolved == null) {
      return const AmountAmbiguous();
    }
    if (resolved.invalidCode != null) {
      return AmountInvalid(resolved.invalidCode!);
    }

    final fraction = resolved.fraction;
    final whole = resolved.whole.isEmpty && fraction.isNotEmpty
        ? '0'
        : resolved.whole;
    if (whole.isEmpty || !RegExp(r'^\d+$').hasMatch(whole)) {
      return const AmountInvalid('amountNotNumeric');
    }
    if (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) {
      return const AmountInvalid('amountNotNumeric');
    }
    if (fraction.length > 2) {
      return const AmountInvalid('amountTooManyDecimals');
    }

    final cents =
        int.parse(whole) * 100 + int.parse(fraction.padRight(2, '0'));
    if (cents > maxCents) {
      return const AmountInvalid('amountOutOfRange');
    }

    return AmountParsed(cents: cents, isNegative: isNegative);
  }

  /// `null` quando il formato è ambiguo e la preferenza è [auto].
  static _SplitAmount? _splitIntoWholeAndFraction(
    String text,
    NumberFormatPreference preference,
  ) {
    final commas = ','.allMatches(text).length;
    final dots = '.'.allMatches(text).length;

    if (commas == 0 && dots == 0) {
      return _SplitAmount(whole: text, fraction: '');
    }

    if (commas > 0 && dots > 0) {
      // L'ultimo separatore è il decimale: nessuna ambiguità possibile.
      final decimalSeparator = text.lastIndexOf(',') > text.lastIndexOf('.')
          ? ','
          : '.';
      return _splitOnDecimalSeparator(text, decimalSeparator);
    }

    final separator = commas > 0 ? ',' : '.';
    final occurrences = commas > 0 ? commas : dots;

    if (occurrences > 1) {
      // Ripetuto: può essere solo separatore delle migliaia.
      return _splitOnThousandsSeparator(text, separator);
    }

    final decimalByPreference = switch (preference) {
      NumberFormatPreference.commaDecimal => ',',
      NumberFormatPreference.dotDecimal => '.',
      NumberFormatPreference.auto => null,
    };

    if (decimalByPreference != null) {
      return decimalByPreference == separator
          ? _splitOnDecimalSeparator(text, separator)
          : _splitOnThousandsSeparator(text, separator);
    }

    final index = text.indexOf(separator);
    final right = text.substring(index + 1);
    final left = text.substring(0, index);

    if (right.length == 3 && left.isNotEmpty && left.length <= 3) {
      // `1.234` / `1,234`: migliaia o decimali, nessuna scelta implicita.
      return null;
    }

    return _splitOnDecimalSeparator(text, separator);
  }

  static _SplitAmount _splitOnDecimalSeparator(String text, String separator) {
    final other = separator == ',' ? '.' : ',';
    final cleaned = text.replaceAll(other, '');
    final parts = cleaned.split(separator);
    if (parts.length != 2) {
      return const _SplitAmount(
        whole: '',
        fraction: '',
        invalidCode: 'amountNotNumeric',
      );
    }
    return _SplitAmount(whole: parts[0], fraction: parts[1]);
  }

  static _SplitAmount _splitOnThousandsSeparator(
    String text,
    String separator,
  ) {
    final groups = text.split(separator);
    final tail = groups.skip(1);
    if (groups.first.isEmpty ||
        groups.first.length > 3 ||
        tail.any((group) => group.length != 3)) {
      return const _SplitAmount(
        whole: '',
        fraction: '',
        invalidCode: 'amountNotNumeric',
      );
    }
    return _SplitAmount(whole: groups.join(), fraction: '');
  }
}

class _SplitAmount {
  const _SplitAmount({
    required this.whole,
    required this.fraction,
    this.invalidCode,
  });

  final String whole;
  final String fraction;
  final String? invalidCode;
}
