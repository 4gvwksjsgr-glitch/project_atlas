import '../../../../core/permissions/company_role.dart';

extension CompanyRoleDbValue on CompanyRole {
  static CompanyRole fromDbValue(String value) {
    return CompanyRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => CompanyRole.employee,
    );
  }
}
