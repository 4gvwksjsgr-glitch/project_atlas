import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

enum CompanyOperation { createCompany, getUserCompanies, countCompanyMembers }

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
    final combined = '$message $details';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (combined.contains('company name is required')) {
      return const ValidationFailure('Il nome azienda è obbligatorio.');
    }

    if (combined.contains('company slug is required')) {
      return const ValidationFailure('Lo slug è obbligatorio.');
    }

    if (combined.contains('invalid slug format')) {
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

    if (combined.contains('infinite recursion detected in policy')) {
      return UnknownFailure(
        'Errore di sicurezza nel caricamento membership: $message',
      );
    }

    if (combined.contains('network') ||
        combined.contains('connection') ||
        combined.contains('timeout')) {
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
    };
  }
}
