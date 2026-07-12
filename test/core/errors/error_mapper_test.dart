import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('ErrorMapper', () {
    test('maps already registered auth error to friendly message', () {
      const error = supabase.AuthException('User already registered');

      final failure = ErrorMapper.mapException(error);

      expect(failure.message, 'Questa email è già registrata.');
    });

    test('maps weak password auth error to friendly message', () {
      const error = supabase.AuthException(
        'Password should be at least 8 characters',
      );

      final failure = ErrorMapper.mapException(error);

      expect(
        failure.message,
        'La password non soddisfa i requisiti di sicurezza.',
      );
    });

    test('does not expose raw technical auth error message', () {
      const error = supabase.AuthException('unexpected_provider_failure_xyz');

      final failure = ErrorMapper.mapException(error);

      expect(failure.message, 'Registrazione non riuscita. Riprova.');
      expect(
        failure.message.contains('unexpected_provider_failure_xyz'),
        isFalse,
      );
    });
  });
}
