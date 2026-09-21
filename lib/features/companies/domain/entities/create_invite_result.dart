import '../../../../core/permissions/company_role.dart';

/// Risultato di create invite: include il token one-time (solo a creazione).
class CreateInviteResult {
  const CreateInviteResult({
    required this.inviteId,
    required this.emailNormalized,
    required this.role,
    required this.expiresAt,
    required this.inviteToken,
  });

  final String inviteId;
  final String emailNormalized;
  final CompanyRole role;
  final DateTime expiresAt;

  /// Token in chiaro restituito una sola volta; non va loggato.
  final String inviteToken;
}
