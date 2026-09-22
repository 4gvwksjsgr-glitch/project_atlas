import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/transaction_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('TransactionErrorMapper', () {
    test(
      'mappa transactions_category_same_company_kind su messaggio categoria IT',
      () {
        final failure = TransactionErrorMapper.mapException(
          const PostgrestException(
            message:
                'insert or update on table "transactions" violates foreign key '
                'constraint "transactions_category_same_company_kind"',
            code: '23503',
          ),
          TransactionOperation.createTransaction,
        );

        expect(failure, isA<ValidationFailure>());
        expect(
          failure.message,
          'La categoria selezionata non è valida per questo movimento.',
        );
      },
    );

    test('mappa transactions_client_same_company su messaggio cliente IT', () {
      final failure = TransactionErrorMapper.mapException(
        const PostgrestException(
          message:
              'insert or update on table "transactions" violates foreign key '
              'constraint "transactions_client_same_company"',
          code: '23503',
        ),
        TransactionOperation.createTransaction,
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        'Il cliente selezionato non appartiene a questa azienda.',
      );
    });

    test('foreign key generico non preferisce il messaggio cliente', () {
      final failure = TransactionErrorMapper.mapException(
        const PostgrestException(
          message:
              'insert or update on table "transactions" violates foreign key '
              'constraint "some_other_fk"',
          code: '23503',
        ),
        TransactionOperation.updateTransaction,
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        'Il riferimento selezionato non è valido per questo movimento.',
      );
      expect(
        failure.message,
        isNot('Il cliente selezionato non appartiene a questa azienda.'),
      );
    });
  });

  group('TransactionErrorMapper codici import', () {
    Failure mapImport(Object error) => TransactionErrorMapper.mapException(
      error,
      TransactionOperation.importTransactions,
    );

    test('file già importato: messaggio che esclude la duplicazione', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_IMPORT_FILE_ALREADY_IMPORTED',
          code: 'P0001',
        ),
      );

      expect(failure, isA<AtlasImportFileAlreadyImportedFailure>());
      expect(failure.message, contains('già stato importato'));
      expect(failure.message, contains('non sono stati duplicati'));
    });

    test('payload non valido', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_IMPORT_PAYLOAD_INVALID',
          code: 'P0001',
        ),
      );

      expect(failure, isA<AtlasImportPayloadInvalidFailure>());
    });

    test('limite di righe superato', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_IMPORT_TOO_MANY_ROWS',
          code: 'P0001',
        ),
      );

      expect(failure, isA<AtlasImportTooManyRowsFailure>());
      expect(failure.message, contains('500'));
    });

    test('import già in corso è un invito ad attendere', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_IMPORT_IN_PROGRESS',
          code: 'P0001',
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('già in corso'));
    });

    test('azienda mancante', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_COMPANY_ID_REQUIRED',
          code: 'P0001',
        ),
      );

      expect(failure, isA<AtlasCompanyIdRequiredFailure>());
    });

    test('sessione scaduta', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'ATLAS_NOT_AUTHENTICATED',
          code: 'P0001',
        ),
      );

      expect(failure, isA<AuthFailure>());
      expect(failure.message, contains('Accedi di nuovo'));
    });

    test('permessi insufficienti sull azienda', () {
      for (final message in const [
        'ATLAS_INSUFFICIENT_PRIVILEGES',
        'ATLAS_NOT_COMPANY_MEMBER',
      ]) {
        final failure = mapImport(
          PostgrestException(message: message, code: 'P0001'),
        );

        expect(failure, isA<AuthFailure>(), reason: message);
        expect(failure.message, contains('permessi'), reason: message);
        expect(failure.message, contains('importare'), reason: message);
      }
    });

    test('codici granulari di validazione sono problemi di payload', () {
      for (final message in const [
        'ATLAS_IMPORT_FILE_NAME_INVALID',
        'ATLAS_IMPORT_FILE_HASH_INVALID',
        'ATLAS_IMPORT_FORMAT_INVALID',
        'ATLAS_IMPORT_DATE_INVALID',
        'ATLAS_IMPORT_KIND_INVALID',
        'ATLAS_IMPORT_AMOUNT_INVALID',
        'ATLAS_IMPORT_DESCRIPTION_INVALID',
        'ATLAS_IMPORT_NOTES_INVALID',
        'ATLAS_IMPORT_REFERENCE_INVALID',
        'ATLAS_IMPORT_ROW_FINGERPRINT_INVALID',
        'ATLAS_IMPORT_DUPLICATE_IN_PAYLOAD',
      ]) {
        final failure = mapImport(
          PostgrestException(message: message, code: 'P0001'),
        );

        expect(
          failure,
          isA<AtlasImportPayloadInvalidFailure>(),
          reason: message,
        );
      }
    });

    test('violazione RLS diventa un errore di permessi', () {
      final failure = mapImport(
        const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
      );

      expect(failure, isA<AuthFailure>());
      expect(failure.message, contains('permessi'));
    });

    test('problema di rete resta un errore di rete', () {
      final failure = mapImport(
        const PostgrestException(message: 'Failed host lookup', code: null),
      );

      expect(failure, isA<NetworkFailure>());
    });

    test('errore sconosciuto usa il fallback import', () {
      final failure = mapImport(
        const PostgrestException(message: 'qualcosa di imprevisto', code: null),
      );

      expect(failure, isA<UnknownFailure>());
      expect(failure.message, 'Importazione movimenti non riuscita. Riprova.');
    });

    test('nessun messaggio di import espone SQL o dati del movimento', () {
      final failure = mapImport(
        const PostgrestException(
          message:
              'ERROR: insert into public.transactions (description) values '
              '(\'Incasso Mario Rossi\') violates ATLAS_IMPORT_AMOUNT_INVALID',
          code: 'P0001',
        ),
      );

      expect(failure.message, isNot(contains('Mario Rossi')));
      expect(failure.message, isNot(contains('insert into')));
      expect(failure.message, isNot(contains('ATLAS_')));
    });
  });
}
