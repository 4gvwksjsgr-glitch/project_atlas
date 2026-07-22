import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/customer_error_mapper.dart';
import 'package:project_atlas/core/errors/exceptions.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('CustomerErrorMapper importCustomers', () {
    Failure map(supabase.PostgrestException error) {
      return CustomerErrorMapper.mapException(
        error,
        CustomerOperation.importCustomers,
      );
    }

    test('file / payload non valido', () {
      final failure = map(
        supabase.PostgrestException(
          message: 'source_row must be a positive integer',
          code: '22023',
        ),
      );
      expect(failure, isA<ValidationFailure>());
      expect(failure.message.toLowerCase(), contains('payload'));
      expect(failure.message, isNot(contains('source_row must')));
      expect(failure.message, isNot(contains('SELECT')));
    });

    test('importazione già in corso', () {
      final failure = map(
        const supabase.PostgrestException(
          message: 'could not obtain lock',
          code: '55P03',
        ),
      );
      expect(failure, isA<ValidationFailure>());
      expect(failure.message.toLowerCase(), contains('già in corso'));
    });

    test('permessi insufficienti', () {
      final failure = map(
        const supabase.PostgrestException(
          message: 'Insufficient permissions',
          code: '42501',
        ),
      );
      expect(failure, isA<AuthFailure>());
      expect(failure.message.toLowerCase(), contains('permessi'));
    });

    test('sessione scaduta', () {
      final failure = map(
        const supabase.PostgrestException(
          message: 'Not authenticated',
          code: '28000',
        ),
      );
      expect(failure, isA<AuthFailure>());
      expect(failure.message.toLowerCase(), contains('sessione'));
    });

    test('rete', () {
      final failure = CustomerErrorMapper.mapException(
        const NetworkException('timeout'),
        CustomerOperation.importCustomers,
      );
      expect(failure, isA<NetworkFailure>());
    });

    test('errore generico senza SQL/payload/PII', () {
      final failure = map(
        supabase.PostgrestException(
          message: 'something broke with Mario Rossi mario@x.com',
          details: '{"name":"Mario","email":"mario@x.com"}',
        ),
      );
      expect(failure, isA<UnknownFailure>());
      expect(failure.message, isNot(contains('Mario')));
      expect(failure.message, isNot(contains('mario@x.com')));
      expect(failure.message, isNot(contains('{')));
      expect(failure.message.toLowerCase(), contains('importazione'));
    });

    test('file non valido lato FormatException repository path', () {
      // Covered via ValidationFailure path in repository for FormatException;
      // mapper falls back for unknown import codes.
      final failure = map(
        const supabase.PostgrestException(message: 'unexpected db fault'),
      );
      expect(failure.message, isNot(contains('unexpected db fault')));
    });
  });
}
