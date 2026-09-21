import '../../../../core/permissions/company_role.dart';

/// Stato di un invito azienda (calcolato lato DB).
enum CompanyInviteStatus { pending, accepted, revoked, expired }

/// Invito a unirsi a un'azienda (senza token in chiaro).
class CompanyInvite {
  const CompanyInvite({
    required this.inviteId,
    required this.emailNormalized,
    required this.role,
    required this.invitedBy,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
    required this.status,
  });

  final String inviteId;
  final String emailNormalized;
  final CompanyRole role;
  final String invitedBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final CompanyInviteStatus status;
}
