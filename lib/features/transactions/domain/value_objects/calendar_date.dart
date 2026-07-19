/// Data calendario senza orario: serializza sempre come `YYYY-MM-DD`.
///
/// Non usa conversioni UTC che potrebbero spostare il giorno.
abstract final class CalendarDate {
  static DateTime dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime todayLocal() => dateOnly(DateTime.now());

  static String toIsoDate(DateTime value) {
    final d = dateOnly(value);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Interpreta `YYYY-MM-DD` come data locale (non UTC).
  static DateTime parseIsoDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('Data non valida (atteso YYYY-MM-DD)', raw);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw FormatException('Data non valida', raw);
    }
    return parsed;
  }

  /// Limiti del mese corrente in data locale (senza UTC).
  ///
  /// [nextMonthStart] è esclusivo: gestisce dicembre→gennaio e febbraio bisestile.
  static ({DateTime monthStart, DateTime nextMonthStart}) currentMonthBounds([
    DateTime? now,
  ]) {
    final today = dateOnly(now ?? DateTime.now());
    final monthStart = DateTime(today.year, today.month, 1);
    final nextMonthStart = DateTime(today.year, today.month + 1, 1);
    return (monthStart: monthStart, nextMonthStart: nextMonthStart);
  }
}
