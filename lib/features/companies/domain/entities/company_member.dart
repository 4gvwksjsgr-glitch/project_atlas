import '../../../../core/permissions/company_role.dart';

/// Membro di un'azienda (vista team).
class CompanyMember {
  const CompanyMember({
    required this.membershipId,
    required this.userId,
    required this.email,
    this.fullName,
    required this.role,
    required this.joinedAt,
  });

  final String membershipId;
  final String userId;
  final String email;
  final String? fullName;
  final CompanyRole role;
  final DateTime joinedAt;
}
