import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

enum CompanyOperation {
  createCompany,
  getUserCompanies,
  countCompanyMembers,
  updateCompany,
}

abstract final class CompanyErrorMapper {
  static Failure mapException(
    Object error, [
    CompanyOperation operation = CompanyOperation.createCompany,
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
    CompanyOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (combined.contains('company name is required')) {
      return const ValidationFailure('Il nome azienda è obbligatorio.');
    }

    if (combined.contains('company slug is required')) {
      return const ValidationFailure('Lo slug è obbligatorio.');
    }

    if (combined.contains('invalid slug format') ||
        combined.contains('companies_slug_format') ||
        (combined.contains('check constraint') && combined.contains('slug'))) {
      return const ValidationFailure(
        'Formato slug non valido. Usa solo lettere minuscole, numeri e trattini.',
      );
    }

    if (error.code == '23505' ||
        combined.contains('duplicate key') ||
        combined.contains('companies_slug_unique')) {
      return const ValidationFailure(
        'Questo slug è già in uso. Scegline un altro.',
      );
    }

    if (error.code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce') ||
        combined.contains('json object requested')) {
      return const AuthFailure(
        'Non hai i permessi per modificare questa azienda.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security')) {
      return const AuthFailure(
        'Non hai i permessi per modificare questa azienda.',
      );
    }

    if (combined.contains('infinite recursion detected in policy')) {
      return UnknownFailure(
        'Errore di sicurezza nel caricamento membership: $message',
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

  static String _fallbackMessage(CompanyOperation operation) {
    return switch (operation) {
      CompanyOperation.createCompany =>
        'Creazione azienda non riuscita. Riprova.',
      CompanyOperation.getUserCompanies =>
        'Caricamento aziende non riuscito. Riprova.',
      CompanyOperation.countCompanyMembers =>
        'Caricamento membri non riuscito. Riprova.',
      CompanyOperation.updateCompany =>
        'Aggiornamento azienda non riuscito. Riprova.',
    };
  }
}
