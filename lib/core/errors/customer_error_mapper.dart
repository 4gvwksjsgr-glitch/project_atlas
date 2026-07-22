import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';

enum CustomerOperation {
  getCustomers,
  createCustomer,
  updateCustomer,
  importCustomers,
}

abstract final class CustomerErrorMapper {
  static Failure mapException(
    Object error, [
    CustomerOperation operation = CustomerOperation.getCustomers,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }

    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }

    if (error is supabase.PostgrestException) {
      return _mapPostgrestException(error, operation);
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static Failure _mapPostgrestException(
    supabase.PostgrestException error,
    CustomerOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';
    final code = error.code ?? '';

    if (operation == CustomerOperation.importCustomers) {
      return _mapImportException(combined, code);
    }

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (error.code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce') ||
        combined.contains('json object requested')) {
      return const AuthFailure(
        'Non hai i permessi per modificare questo cliente.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security') ||
        combined.contains('insufficient permissions')) {
      return const AuthFailure(
        'Non hai i permessi per gestire i clienti di questa azienda.',
      );
    }

    if (combined.contains('clients_name_not_empty') ||
        combined.contains('name')) {
      if (combined.contains('check constraint') ||
          combined.contains('not-null') ||
          combined.contains('null value')) {
        return const ValidationFailure('Il nome cliente è obbligatorio.');
      }
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

  /// Localized import failures without SQL, JSON payload, or personal data.
  static Failure _mapImportException(String combined, String code) {
    if (combined.contains('not authenticated') || code == '28000') {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (combined.contains('insufficient permissions') ||
        combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        code == '42501') {
      return const AuthFailure(
        'Non hai i permessi per importare clienti in questa azienda.',
      );
    }

    if (combined.contains('import already in progress') ||
        combined.contains('could not obtain lock') ||
        combined.contains('lock_not_available')) {
      return const ValidationFailure(
        'Importazione già in corso per questa azienda. Riprova tra poco.',
      );
    }

    if (combined.contains('rows must be') ||
        combined.contains('source_row') ||
        combined.contains('unexpected field') ||
        combined.contains('company_id must not') ||
        combined.contains('each row must') ||
        combined.contains('invalid name') ||
        combined.contains('email must') ||
        combined.contains('phone must') ||
        combined.contains('notes must') ||
        combined.contains('too long') ||
        combined.contains('invalid_parameter') ||
        code == '22023') {
      return const ValidationFailure(
        'Payload di importazione non valido. Controlla il file e riprova.',
      );
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

    return const UnknownFailure('Importazione clienti non riuscita. Riprova.');
  }

  static String _fallbackMessage(CustomerOperation operation) {
    return switch (operation) {
      CustomerOperation.getCustomers =>
        'Caricamento clienti non riuscito. Riprova.',
      CustomerOperation.createCustomer =>
        'Creazione cliente non riuscita. Riprova.',
      CustomerOperation.updateCustomer =>
        'Aggiornamento cliente non riuscito. Riprova.',
      CustomerOperation.importCustomers =>
        'Importazione clienti non riuscita. Riprova.',
    };
  }
}
