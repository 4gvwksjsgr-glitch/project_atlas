import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/exceptions.dart';
import '../errors/failures.dart';

enum CategoryOperation {
  getCategories,
  createCategory,
  renameCategory,
  setCategoryActive,
}

abstract final class CategoryErrorMapper {
  static Failure mapException(
    Object error, [
    CategoryOperation operation = CategoryOperation.getCategories,
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
    CategoryOperation operation,
  ) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final combined = '$message $details $hint';
    final code = error.code ?? '';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce') ||
        combined.contains('json object requested')) {
      return const AuthFailure(
        'Non hai i permessi per modificare questa categoria.',
      );
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('violates row-level security') ||
        combined.contains('insufficient permissions')) {
      return const AuthFailure(
        'Non hai i permessi per gestire le categorie di questa azienda.',
      );
    }

    if (code == '23505' ||
        combined.contains('transaction_categories_company_kind_lower_name') ||
        combined.contains('duplicate key')) {
      return const ValidationFailure(
        'Esiste già una categoria con questo nome per lo stesso tipo.',
      );
    }

    if (combined.contains('transaction_categories_name_max_len') ||
        (combined.contains('name') && combined.contains('check'))) {
      if (combined.contains('max_len') || combined.contains('80')) {
        return const ValidationFailure(
          'Il nome della categoria non può superare i 80 caratteri.',
        );
      }
      if (combined.contains('not_empty') ||
          combined.contains('trimmed') ||
          combined.contains('not-null')) {
        return const ValidationFailure(
          'Il nome della categoria è obbligatorio.',
        );
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

  static String _fallbackMessage(CategoryOperation operation) {
    return switch (operation) {
      CategoryOperation.getCategories =>
        'Caricamento categorie non riuscito. Riprova.',
      CategoryOperation.createCategory =>
        'Creazione categoria non riuscita. Riprova.',
      CategoryOperation.renameCategory =>
        'Rinomina categoria non riuscita. Riprova.',
      CategoryOperation.setCategoryActive =>
        'Aggiornamento stato categoria non riuscito. Riprova.',
    };
  }
}
