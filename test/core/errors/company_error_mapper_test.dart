import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/company_error_mapper.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('CompanyErrorMapper', () {
    test('mappa slug duplicato su ValidationFailure', () {
      final failure = CompanyErrorMapper.mapException(
        const supabase.PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('slug'));
    });

    test('mappa slug non valido su ValidationFailure', () {
      final failure = CompanyErrorMapper.mapException(
        const supabase.PostgrestException(
          message: 'Invalid slug format',
          code: '22023',
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('slug'));
    });

    test('mappa PGRST116 su AuthFailure per update senza riga', () {
      final failure = CompanyErrorMapper.mapException(
        const supabase.PostgrestException(
          message: 'JSON object requested, multiple (or no) rows returned',
          code: 'PGRST116',
        ),
        CompanyOperation.updateCompany,
      );

      expect(failure, isA<AuthFailure>());
      expect(
        failure.message,
        'Non hai i permessi per modificare questa azienda.',
      );
    });

    test(
      'permission denied su getCompanyCashSummary usa messaggio di visualizzazione',
      () {
        final byText = CompanyErrorMapper.mapException(
          const supabase.PostgrestException(
            message: 'permission denied for schema private',
            code: '42501',
          ),
          CompanyOperation.getCompanyCashSummary,
        );
        expect(byText, isA<AuthFailure>());
        expect(
          byText.message,
          'Non hai i permessi per visualizzare il riepilogo economico.',
        );

        final byCode = CompanyErrorMapper.mapException(
          const supabase.PostgrestException(
            message: 'Insufficient privilege',
            code: '42501',
          ),
          CompanyOperation.getCompanyCashSummary,
        );
        expect(
          byCode.message,
          'Non hai i permessi per visualizzare il riepilogo economico.',
        );
      },
    );

    test(
      'permission denied su updateCompany mantiene messaggio di modifica',
      () {
        final failure = CompanyErrorMapper.mapException(
          const supabase.PostgrestException(
            message: 'permission denied for table companies',
            code: '42501',
          ),
          CompanyOperation.updateCompany,
        );

        expect(failure, isA<AuthFailure>());
        expect(
          failure.message,
          'Non hai i permessi per modificare questa azienda.',
        );
      },
    );
  });
}
