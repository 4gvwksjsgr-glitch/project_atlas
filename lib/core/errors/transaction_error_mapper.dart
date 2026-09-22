import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/atlas_error_codes.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';

enum TransactionOperation {
  getTransactions,
  createTransaction,
  updateTransaction,
  importTransactions,
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

    if (operation == TransactionOperation.importTransactions) {
      final atlasFailure = _mapAtlasImportCode(AtlasErrorCodes.extract(error));
      if (atlasFailure != null) {
        return atlasFailure;
      }
    }

    if (error is FormatException) {
      return ValidationFailure(error.message);
    }

    if (error is supabase.PostgrestException) {
      return _mapPostgrestException(error, operation);
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  /// Codici applicativi della RPC `import_transactions`.
  static Failure? _mapAtlasImportCode(String? code) {
    return switch (code) {
      AtlasErrorCodes.importFileAlreadyImported =>
        const AtlasImportFileAlreadyImportedFailure(),
      AtlasErrorCodes.importPayloadInvalid =>
        const AtlasImportPayloadInvalidFailure(),
      AtlasErrorCodes.importTooManyRows => const AtlasImportTooManyRowsFailure(),
      AtlasErrorCodes.importInProgress => const ValidationFailure(
        'Importazione già in corso per questa azienda. Riprova tra poco.',
      ),
      AtlasErrorCodes.notAuthenticated => const AuthFailure(
        'Sessione scaduta. Accedi di nuovo.',
      ),
      AtlasErrorCodes.insufficientPrivileges ||
      AtlasErrorCodes.notCompanyMember => const AuthFailure(
        'Non hai i permessi per importare movimenti in questa azienda.',
      ),
      AtlasErrorCodes.companyIdRequired =>
        const AtlasCompanyIdRequiredFailure(),
      _ => null,
    };
  }

  static Failure _mapPostgrestException(
    supabase.PostgrestException error,
    TransactionOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';

    if (operation == TransactionOperation.importTransactions) {
      return _mapImportException(combined, error.code ?? '');
    }

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

  /// Errori di import senza SQL, payload o dati del movimento.
  static Failure _mapImportException(String combined, String code) {
    if (combined.contains('not authenticated') || code == '28000') {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (combined.contains('insufficient permissions') ||
        combined.contains('insufficient privileges') ||
        combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        code == '42501') {
      return const AuthFailure(
        'Non hai i permessi per importare movimenti in questa azienda.',
      );
    }

    if (combined.contains('already imported') ||
        combined.contains('source_file_sha256')) {
      return const AtlasImportFileAlreadyImportedFailure();
    }

    if (combined.contains('import already in progress') ||
        combined.contains('could not obtain lock') ||
        combined.contains('lock_not_available')) {
      return const ValidationFailure(
        'Importazione già in corso per questa azienda. Riprova tra poco.',
      );
    }

    if (combined.contains('too many rows')) {
      return const AtlasImportTooManyRowsFailure();
    }

    // Codici granulari della RPC (`ATLAS_IMPORT_<campo>_INVALID`,
    // `ATLAS_IMPORT_DUPLICATE_IN_PAYLOAD`): il payload va corretto, non
    // ritentato.
    if (combined.contains('atlas_import_') &&
        (combined.contains('_invalid') ||
            combined.contains('duplicate_in_payload'))) {
      return const AtlasImportPayloadInvalidFailure();
    }

    if (combined.contains('rows must be') ||
        combined.contains('source_row') ||
        combined.contains('row_fingerprint') ||
        combined.contains('unexpected field') ||
        combined.contains('company_id must not') ||
        combined.contains('each row must') ||
        combined.contains('occurred_on') ||
        combined.contains('invalid kind') ||
        combined.contains('amount must') ||
        combined.contains('invalid_parameter') ||
        code == '22023') {
      return const AtlasImportPayloadInvalidFailure();
    }

    if (combined.contains('network') ||
        combined.contains('connection') ||
        combined.contains('timeout') ||
        combined.contains('failed host lookup') ||
        combined.contains('socketexception')) {
      return const NetworkFailure(
        'Connessione non disponibile. Verifica la rete e riprova.',
      );
    }

    return const UnknownFailure(
      'Importazione movimenti non riuscita. Riprova.',
    );
  }

  static String _fallbackMessage(TransactionOperation operation) {
    return switch (operation) {
      TransactionOperation.getTransactions =>
        'Caricamento movimenti non riuscito. Riprova.',
      TransactionOperation.createTransaction =>
        'Creazione movimento non riuscita. Riprova.',
      TransactionOperation.updateTransaction =>
        'Aggiornamento movimento non riuscito. Riprova.',
      TransactionOperation.importTransactions =>
        'Importazione movimenti non riuscita. Riprova.',
    };
  }
}
