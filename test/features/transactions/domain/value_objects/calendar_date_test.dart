import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/calendar_date.dart';

void main() {
  group('CalendarDate.toIsoDate / parseIsoDate', () {
    test('round-trip senza spostamenti dovuti a UTC', () {
      final local = DateTime(2026, 7, 17, 23, 45);
      final iso = CalendarDate.toIsoDate(local);
      expect(iso, '2026-07-17');

      final parsed = CalendarDate.parseIsoDate(iso);
      expect(parsed.year, 2026);
      expect(parsed.month, 7);
      expect(parsed.day, 17);
      expect(parsed.isUtc, isFalse);
    });

    test('round-trip vicino alla mezzanotte non cambia giorno', () {
      final local = DateTime(2026, 1, 1, 0, 5);
      final iso = CalendarDate.toIsoDate(local);
      expect(iso, '2026-01-01');
      expect(CalendarDate.parseIsoDate(iso), DateTime(2026, 1, 1));
    });

    test('parse di "2026-07-17" restituisce anno/mese/giorno locali', () {
      final parsed = CalendarDate.parseIsoDate('2026-07-17');
      expect(parsed.year, 2026);
      expect(parsed.month, 7);
      expect(parsed.day, 17);
      expect(parsed, DateTime(2026, 7, 17));
    });

    test('rifiuta formati non validi', () {
      expect(
        () => CalendarDate.parseIsoDate('17-07-2026'),
        throwsFormatException,
      );
      expect(
        () => CalendarDate.parseIsoDate('2026/07/17'),
        throwsFormatException,
      );
      expect(
        () => CalendarDate.parseIsoDate('not-a-date'),
        throwsFormatException,
      );
    });

    test('rifiuta date calendario inesistenti', () {
      expect(
        () => CalendarDate.parseIsoDate('2026-02-30'),
        throwsFormatException,
      );
      expect(
        () => CalendarDate.parseIsoDate('2026-13-01'),
        throwsFormatException,
      );
    });
  });

  group('CalendarDate.dateOnly', () {
    test('elimina la componente orario', () {
      final withTime = DateTime(2026, 7, 17, 14, 30, 15, 500);
      final onlyDate = CalendarDate.dateOnly(withTime);

      expect(onlyDate, DateTime(2026, 7, 17));
      expect(onlyDate.hour, 0);
      expect(onlyDate.minute, 0);
      expect(onlyDate.second, 0);
      expect(onlyDate.millisecond, 0);
    });
  });

  group('CalendarDate.todayLocal', () {
    test('restituisce sempre una data senza orario', () {
      final today = CalendarDate.todayLocal();
      expect(today, CalendarDate.dateOnly(today));
    });
  });
}
