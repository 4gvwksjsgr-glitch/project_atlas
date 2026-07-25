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
}
