import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

enum AuthOperation {
  signUp,
  signIn,
  signOut,
  resetPassword,
  updatePassword,
  getSession,
}

abstract final class ErrorMapper {
  static Failure mapException(
    Object error, [
    AuthOperation operation = AuthOperation.signUp,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }

    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }

    if (error is supabase.AuthException) {
      return AuthFailure(_mapSupabaseAuthMessage(error, operation));
    }

    return UnknownFailure(_fallbackMessage(operation));
  }

  static AuthException mapSupabaseAuthException(supabase.AuthException error) {
    return AuthException(_mapSupabaseAuthMessage(error, AuthOperation.signUp));
  }

  static String _mapSupabaseAuthMessage(
    supabase.AuthException error,
    AuthOperation operation,
  ) {
    final message = error.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already registered')) {
      return 'Questa email è già registrata.';
    }

    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials')) {
      return 'Email o password non corretti.';
    }

    if (message.contains('password') &&
        (message.contains('weak') ||
            message.contains('short') ||
            message.contains('at least') ||
            message.contains('same'))) {
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

    return _fallbackMessage(operation);
  }

  static String _fallbackMessage(AuthOperation operation) {
    return switch (operation) {
      AuthOperation.signUp => 'Registrazione non riuscita. Riprova.',
      AuthOperation.signIn => 'Accesso non riuscito. Riprova.',
      AuthOperation.signOut => 'Disconnessione non riuscita. Riprova.',
      AuthOperation.resetPassword => 'Invio del link non riuscito. Riprova.',
      AuthOperation.updatePassword =>
        'Aggiornamento password non riuscito. Riprova.',
      AuthOperation.getSession => 'Sessione non disponibile. Riprova.',
    };
  }
}
