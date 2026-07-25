import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';

enum TransactionOperation {
  getTransactions,
  createTransaction,
  updateTransaction,
}

abstract final class TransactionErrorMapper {
  static Failure mapException(
    Object error, [
    TransactionOperation operation = TransactionOperation.getTransactions,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }

    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }

    if (error is FormatException) {
      return ValidationFailure(error.message);
    }

    if (error is supabase.PostgrestException) {
      return _mapPostgrestException(error, operation);
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static Failure _mapPostgrestException(
    supabase.PostgrestException error,
    TransactionOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (error.code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce') ||
        combined.contains('json object requested')) {
      return const AuthFailure(
        'Non hai i permessi per modificare questo movimento.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security')) {
      return const AuthFailure(
        'Non hai i permessi per gestire i movimenti di questa azienda.',
      );
    }

    if (combined.contains('company_id cannot be changed')) {
      return const ValidationFailure(
        'L\'azienda del movimento non può essere modificata.',
      );
    }

    if (combined.contains('transactions_amount_positive') ||
        (combined.contains('amount') &&
            (combined.contains('check constraint') ||
                combined.contains('violates check')))) {
      return const ValidationFailure(
        'L\'importo deve essere maggiore di zero.',
      );
    }

    if (combined.contains('transactions_description_not_empty') ||
        (combined.contains('description') &&
            (combined.contains('check constraint') ||
                combined.contains('not-null') ||
                combined.contains('null value')))) {
      return const ValidationFailure('La descrizione è obbligatoria.');
    }

    if (combined.contains('transactions_category_same_company_kind')) {
      return const ValidationFailure(
        'La categoria selezionata non è valida per questo movimento.',
      );
    }

    if (combined.contains('transactions_client_same_company')) {
      return const ValidationFailure(
        'Il cliente selezionato non appartiene a questa azienda.',
      );
    }

    if (combined.contains('foreign key')) {
      return const ValidationFailure(
        'Il riferimento selezionato non è valido per questo movimento.',
      );
    }

    if (combined.contains('network') ||
        combined.contains('connection') ||
        combined.contains('timeout') ||
        combined.contains('failed host lookup') ||
        combined.contains('socketexception')) {
      return const NetworkFailure();
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static String _fallbackMessage(TransactionOperation operation) {
    return switch (operation) {
      TransactionOperation.getTransactions =>
        'Caricamento movimenti non riuscito. Riprova.',
      TransactionOperation.createTransaction =>
        'Creazione movimento non riuscita. Riprova.',
      TransactionOperation.updateTransaction =>
        'Aggiornamento movimento non riuscito. Riprova.',
    };
  }
}
