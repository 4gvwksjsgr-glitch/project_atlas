import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'exceptions.dart';
import 'failures.dart';

enum TeamOperation {
  listMembers,
  listInvites,
  createInvite,
  revokeInvite,
  acceptInvite,
  changeMemberRole,
  removeMember,
}

/// Mappa errori team / invitati (codici ATLAS_* e messaggi trigger).
abstract final class TeamErrorMapper {
  static const _codes = <String>{
    'ATLAS_NOT_AUTHENTICATED',
    'ATLAS_INSUFFICIENT_PRIVILEGES',
    'ATLAS_NOT_COMPANY_MEMBER',
    'ATLAS_INVITE_EMAIL_INVALID',
    'ATLAS_INVITE_ROLE_OWNER_FORBIDDEN',
    'ATLAS_INVITE_ADMIN_ROLE_OWNER_ONLY',
    'ATLAS_INVITE_ALREADY_MEMBER',
    'ATLAS_INVITE_ALREADY_PENDING',
    'ATLAS_INVITE_NOT_FOUND',
    'ATLAS_INVITE_ALREADY_ACCEPTED',
    'ATLAS_INVITE_REVOKED',
    'ATLAS_INVITE_EXPIRED',
    'ATLAS_INVITE_EMAIL_MISMATCH',
    'ATLAS_INVITE_EMAIL_UNVERIFIED',
    'ATLAS_INVITE_TOKEN_REQUIRED',
    'ATLAS_MEMBER_NOT_FOUND',
    'ATLAS_CANNOT_REMOVE_LAST_OWNER',
    'ATLAS_ONLY_OWNER_CAN_ASSIGN_OWNER',
    'ATLAS_ONLY_OWNER_CAN_ASSIGN_ADMIN',
  };

  static Failure mapException(
    Object error, [
    TeamOperation operation = TeamOperation.listMembers,
  ]) {
    if (error is AuthException) {
      return AuthFailure(error.message);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    if (error is FormatException) {
      return ValidationFailure(
        error.message.isNotEmpty
            ? error.message
            : 'Risposta del server non valida.',
      );
    }
    if (error is Failure) {
      return error;
    }

    final atlasCode = _extractAtlasCode(error);
    if (atlasCode != null) {
      return mapAtlasCode(atlasCode);
    }

    if (error is supabase.PostgrestException) {
      return _mapPostgrest(error, operation);
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
      'ATLAS_NOT_AUTHENTICATED' => const AuthFailure(
        'Sessione scaduta. Accedi di nuovo.',
      ),
      'ATLAS_INSUFFICIENT_PRIVILEGES' => const AuthFailure(
        'Non hai i permessi per gestire i membri di questa azienda.',
      ),
      'ATLAS_NOT_COMPANY_MEMBER' => const AuthFailure(
        'Non fai parte di questa azienda.',
      ),
      'ATLAS_INVITE_EMAIL_INVALID' => const ValidationFailure(
        'Indirizzo email non valido.',
      ),
      'ATLAS_INVITE_ROLE_OWNER_FORBIDDEN' => const ValidationFailure(
        'Non è possibile invitare con il ruolo proprietario.',
      ),
      'ATLAS_INVITE_ADMIN_ROLE_OWNER_ONLY' => const AuthFailure(
        'Solo il proprietario può invitare un amministratore.',
      ),
      'ATLAS_INVITE_ALREADY_MEMBER' => const ValidationFailure(
        'Questa email corrisponde già a un membro dell\'azienda.',
      ),
      'ATLAS_INVITE_ALREADY_PENDING' => const ValidationFailure(
        'Esiste già un invito in sospeso per questa email.',
      ),
      'ATLAS_INVITE_NOT_FOUND' => const ValidationFailure(
        'Invito non trovato.',
      ),
      'ATLAS_INVITE_ALREADY_ACCEPTED' => const ValidationFailure(
        'Questo invito è già stato accettato.',
      ),
      'ATLAS_INVITE_REVOKED' => const ValidationFailure(
        'Questo invito è stato revocato.',
      ),
      'ATLAS_INVITE_EXPIRED' => const ValidationFailure(
        'Questo invito è scaduto.',
      ),
      'ATLAS_INVITE_EMAIL_MISMATCH' => const ValidationFailure(
        'L\'email del tuo account non corrisponde a quella dell\'invito.',
      ),
      'ATLAS_INVITE_EMAIL_UNVERIFIED' => const ValidationFailure(
        'Verifica l\'email del tuo account prima di accettare l\'invito.',
      ),
      'ATLAS_INVITE_TOKEN_REQUIRED' => const ValidationFailure(
        'Inserisci il token di invito.',
      ),
      'ATLAS_MEMBER_NOT_FOUND' => const ValidationFailure(
        'Membro non trovato.',
      ),
      'ATLAS_CANNOT_REMOVE_LAST_OWNER' => const ValidationFailure(
        'Non puoi rimuovere l\'ultimo proprietario.',
      ),
      'ATLAS_ONLY_OWNER_CAN_ASSIGN_OWNER' => const AuthFailure(
        'Solo il proprietario può assegnare il ruolo proprietario.',
      ),
      'ATLAS_ONLY_OWNER_CAN_ASSIGN_ADMIN' => const AuthFailure(
        'Solo il proprietario può assegnare il ruolo amministratore.',
      ),
      _ => const UnknownFailure(),
    };
  }

  static Failure _mapPostgrest(
    supabase.PostgrestException error,
    TeamOperation operation,
  ) {
    final combined =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}';
    final lower = combined.toLowerCase();

    if (lower.contains('cannot remove the last owner') ||
        lower.contains('cannot demote the last owner')) {
      return const ValidationFailure(
        'Non puoi rimuovere o declassare l\'ultimo proprietario.',
      );
    }

    if (lower.contains('not authenticated')) {
      return const AuthFailure('Sessione scaduta. Accedi di nuovo.');
    }

    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return const NetworkFailure();
    }

    return UnknownFailure(_fallback(operation));
  }

  static String? _extractAtlasCode(Object error) {
    final parts = <String>[];
    if (error is supabase.PostgrestException) {
      parts.add(error.message);
      final details = error.details?.toString();
      if (details != null) parts.add(details);
      if (error.hint != null) parts.add(error.hint!);
      if (error.code != null) parts.add(error.code!);
    } else {
      parts.add(error.toString());
    }

    for (final part in parts) {
      final upper = part.toUpperCase();
      for (final code in _codes) {
        if (upper.contains(code)) {
          return code;
        }
      }
    }
    return null;
  }

  static String _fallback(TeamOperation operation) {
    return switch (operation) {
      TeamOperation.listMembers =>
        'Caricamento membri non riuscito. Riprova.',
      TeamOperation.listInvites =>
        'Caricamento inviti non riuscito. Riprova.',
      TeamOperation.createInvite =>
        'Creazione invito non riuscita. Riprova.',
      TeamOperation.revokeInvite =>
        'Revoca invito non riuscita. Riprova.',
      TeamOperation.acceptInvite =>
        'Accettazione invito non riuscita. Riprova.',
      TeamOperation.changeMemberRole =>
        'Cambio ruolo non riuscito. Riprova.',
      TeamOperation.removeMember =>
        'Rimozione membro non riuscita. Riprova.',
    };
  }
}
