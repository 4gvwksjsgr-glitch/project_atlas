import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'atlas_error_codes.dart';
import 'exceptions.dart';
import 'failures.dart';

enum ReferralOperation {
  getOverview,
  getOrCreateLink,
  regenerateLink,
  claim,
}

abstract final class ReferralErrorMapper {
  static Failure mapException(
    Object error, [
    ReferralOperation operation = ReferralOperation.getOverview,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is FormatException) {
      return const ValidationFailure(
        'Risposta del server non valida per i referral.',
      );
    }
    if (error is ArgumentError) {
      return ValidationFailure(error.message ?? 'Parametro non valido.');
    }
    if (error is Failure) {
      return error;
    }

    final atlasCode = AtlasErrorCodes.extract(error);
    if (atlasCode != null) {
      return mapAtlasCode(atlasCode);
    }

    if (error is supabase.PostgrestException) {
      return UnknownFailure(_fallback(operation));
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

  static Failure mapAtlasCode(String code) {
    return switch (code) {
      AtlasErrorCodes.notAuthenticated => const AuthFailure(
        'La sessione non è valida. Accedi nuovamente.',
      ),
      AtlasErrorCodes.insufficientPrivileges => const AuthFailure(
        'Non hai i permessi per gestire i referral di questa azienda.',
      ),
      AtlasErrorCodes.companyIdRequired =>
        const AtlasCompanyIdRequiredFailure(),
      AtlasErrorCodes.referralCodeInvalid => const ValidationFailure(
        'Il codice referral non è valido.',
      ),
      AtlasErrorCodes.referralClaimWindowClosed => const ValidationFailure(
        'Non è più possibile reclamare un codice referral.',
      ),
      AtlasErrorCodes.referralSelfDenied => const ValidationFailure(
        'Non puoi usare il codice referral della tua azienda.',
      ),
      AtlasErrorCodes.referralCodeGenerateFailed => const UnknownFailure(
        'Generazione del codice referral non riuscita. Riprova.',
      ),
      _ => const UnknownFailure(),
    };
  }

  /// Terminal claim outcomes: clear pending code. Network/unknown keep it.
  static bool isTerminalClaimFailure(Failure failure) {
    if (failure is! ValidationFailure) {
      return false;
    }
    return failure.message == 'Il codice referral non è valido.' ||
        failure.message == 'Non è più possibile reclamare un codice referral.' ||
        failure.message == 'Non puoi usare il codice referral della tua azienda.';
  }

  static String _fallback(ReferralOperation operation) {
    return switch (operation) {
      ReferralOperation.getOverview =>
        'Caricamento referral non riuscito. Riprova.',
      ReferralOperation.getOrCreateLink =>
        'Creazione link referral non riuscita. Riprova.',
      ReferralOperation.regenerateLink =>
        'Rigenerazione link referral non riuscita. Riprova.',
      ReferralOperation.claim =>
        'Reclamo del codice referral non riuscito. Riprova.',
    };
  }
}
