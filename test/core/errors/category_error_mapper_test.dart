import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/category_error_mapper.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('CategoryErrorMapper', () {
    test('mappa duplicato case-insensitive su ValidationFailure IT', () {
      final failure = CategoryErrorMapper.mapException(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint '
              '"transaction_categories_company_kind_lower_name_unique"',
          code: '23505',
        ),
        CategoryOperation.createCategory,
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        'Esiste già una categoria con questo nome per lo stesso tipo.',
      );
    });

    test('mappa permission denied su AuthFailure', () {
      final failure = CategoryErrorMapper.mapException(
        const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
        CategoryOperation.createCategory,
      );

      expect(failure, isA<AuthFailure>());
    });
  });
}
