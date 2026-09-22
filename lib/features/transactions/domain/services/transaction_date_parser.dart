import '../value_objects/transaction_import_formats.dart';

sealed class DateParseOutcome {
  const DateParseOutcome();
}

final class DateParsed extends DateParseOutcome {
  const DateParsed(this.value);

  /// Data locale senza orario, coerente con `CalendarDate`.
  final DateTime value;

  @override
  String toString() => 'DateParsed()';
}

/// Giorno e mese sono entrambi plausibili: serve una scelta esplicita.
final class DateAmbiguous extends DateParseOutcome {
  const DateAmbiguous();

  @override
  String toString() => 'DateAmbiguous()';
}

final class DateInvalid extends DateParseOutcome {
  const DateInvalid(this.code);

  final String code;

  @override
  String toString() => 'DateInvalid($code)';
}

/// Legge `YYYY-MM-DD`, `DD/MM/YYYY`, `DD-MM-YYYY` e le varianti con `/`, `-`
/// o `.`. Gli anni a due cifre non sono supportati (nessuna regola di secolo
/// inventata) e le date impossibili sono rifiutate.
abstract final class TransactionDateParser {
  static DateParseOutcome parse(
    String raw, {
    DateFormatPreference preference = DateFormatPreference.auto,
  }) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const DateInvalid('dateMissing');
    }

    // Le celle XLSX data arrivano già come `YYYY-MM-DD` con orario azzerato.
    final isoWithTime = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ]').firstMatch(text);
    final normalized = isoWithTime == null ? text : text.substring(0, 10);

    final parts = normalized.split(RegExp(r'[-/.]'));
    if (parts.length != 3 || parts.any((p) => !RegExp(r'^\d+$').hasMatch(p))) {
      return const DateInvalid('dateUnsupportedFormat');
    }

    if (parts[0].length == 4) {
      return _build(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }

    if (parts[2].length != 4) {
      return const DateInvalid('dateUnsupportedFormat');
    }

    final year = int.parse(parts[2]);
    final first = int.parse(parts[0]);
    final second = int.parse(parts[1]);

    final asDmy = _tryDate(year, second, first);
    final asMdy = _tryDate(year, first, second);

    switch (preference) {
      case DateFormatPreference.dmy:
        return asDmy == null ? const DateInvalid('dateInvalid') : DateParsed(asDmy);
      case DateFormatPreference.mdy:
        return asMdy == null ? const DateInvalid('dateInvalid') : DateParsed(asMdy);
      case DateFormatPreference.ymd:
      case DateFormatPreference.auto:
        break;
    }

    if (asDmy == null && asMdy == null) {
      return const DateInvalid('dateInvalid');
    }
    if (asDmy != null && asMdy == null) {
      return DateParsed(asDmy);
    }
    if (asMdy != null && asDmy == null) {
      return DateParsed(asMdy);
    }
    if (asDmy == asMdy) {
      return DateParsed(asDmy!);
    }
    return const DateAmbiguous();
  }

  static DateParseOutcome _build(int year, int month, int day) {
    final value = _tryDate(year, month, day);
    return value == null ? const DateInvalid('dateInvalid') : DateParsed(value);
  }

  static DateTime? _tryDate(int year, int month, int day) {
    if (year < 1900 || year > 2999 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }
}
