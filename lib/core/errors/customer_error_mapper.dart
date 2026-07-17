import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';

enum CustomerOperation { getCustomers, createCustomer, updateCustomer }

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
        combined.contains('violates row-level security')) {
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

  static String _fallbackMessage(CustomerOperation operation) {
    return switch (operation) {
      CustomerOperation.getCustomers =>
        'Caricamento clienti non riuscito. Riprova.',
      CustomerOperation.createCustomer =>
        'Creazione cliente non riuscita. Riprova.',
      CustomerOperation.updateCustomer =>
        'Aggiornamento cliente non riuscito. Riprova.',
    };
  }
}
