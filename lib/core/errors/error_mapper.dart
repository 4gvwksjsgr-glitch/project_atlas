import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

abstract final class ErrorMapper {
  static Failure mapException(Object error) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }

    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }

    if (error is supabase.AuthException) {
      return AuthFailure(_mapSupabaseAuthMessage(error));
    }

    return const UnknownFailure();
  }

  static AuthException mapSupabaseAuthException(supabase.AuthException error) {
    return AuthException(_mapSupabaseAuthMessage(error));
  }

  static String _mapSupabaseAuthMessage(supabase.AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already registered')) {
      return 'Questa email è già registrata.';
    }

    if (message.contains('password') &&
        (message.contains('weak') ||
            message.contains('short') ||
            message.contains('at least'))) {
      return 'La password non soddisfa i requisiti di sicurezza.';
    }

    if (message.contains('invalid email')) {
      return 'Inserisci un\'email valida.';
    }

    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout')) {
      return 'Errore di rete. Riprova.';
    }

    return 'Registrazione non riuscita. Riprova.';
  }
}
