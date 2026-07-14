import '../../../../core/permissions/company_role.dart';
import 'company.dart';

/// Membership di un utente in un'azienda.
class CompanyMembership {
  const CompanyMembership({
    required this.id,
    required this.companyId,
    required this.role,
    required this.joinedAt,
    required this.company,
  });

  final String id;
  final String companyId;
  final CompanyRole role;
  final DateTime joinedAt;
  final Company company;
}
