import '../../../../core/permissions/company_role.dart';
import 'company.dart';

/// Contesto operativo dell'azienda attiva per l'utente autenticato.
class ActiveCompanyContext {
  const ActiveCompanyContext({
    required this.companyId,
    required this.companyName,
    required this.companySlug,
    required this.role,
    required this.membershipId,
  });

  final String companyId;
  final String companyName;
  final String companySlug;
  final CompanyRole role;
  final String membershipId;

  Company toCompany({
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return Company(
      id: companyId,
      name: companyName,
      slug: companySlug,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
