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
  });
}
