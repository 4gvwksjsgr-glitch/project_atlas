import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

enum SubscriptionOperation { getOverview }

abstract final class SubscriptionErrorMapper {
  static Failure mapException(
    Object error, [
    SubscriptionOperation operation = SubscriptionOperation.getOverview,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is FormatException) {
      return const ValidationFailure(
        'Risposta del server non valida per il piano.',
      );
    }
    if (error is Failure) {
      return error;
    }

    if (error is supabase.PostgrestException) {
      return _mapPostgrest(error);
    }

    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('timeout') ||
        text.contains('failed host lookup')) {
      return const NetworkFailure();
    }

    return UnknownFailure(_fallback(operation));
  }

  static Failure _mapPostgrest(supabase.PostgrestException error) {
    final combined =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    final code = error.code ?? '';

    if (combined.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }
    if (combined.contains('not a company member') || code == '42501') {
      return const AuthFailure(
        'Non hai i permessi per visualizzare il piano di questa azienda.',
      );
    }
    if (combined.contains('subscription not found') ||
        (code == 'P0002' && combined.contains('subscription'))) {
      return const SubscriptionNotFoundFailure();
    }
    if (combined.contains('plan not found') ||
        (code == 'P0002' && combined.contains('plan'))) {
      return const SubscriptionPlanNotFoundFailure();
    }
    if (code == 'PGRST116' ||
        combined.contains('0 rows') ||
        combined.contains('cannot coerce')) {
      return const SubscriptionNotFoundFailure();
    }

    return UnknownFailure(_fallback(SubscriptionOperation.getOverview));
  }

  static String _fallback(SubscriptionOperation operation) {
    return switch (operation) {
      SubscriptionOperation.getOverview =>
        'Caricamento piano non riuscito. Riprova.',
    };
  }
}
