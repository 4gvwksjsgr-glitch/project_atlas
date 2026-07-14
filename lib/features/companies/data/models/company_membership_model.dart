import '../../domain/entities/company_membership.dart';
import 'company_model.dart';
import 'company_role_mapper.dart';

class CompanyMembershipModel {
  const CompanyMembershipModel({
    required this.id,
    required this.companyId,
    required this.role,
    required this.joinedAt,
    required this.company,
  });

  final String id;
  final String companyId;
  final String role;
  final DateTime joinedAt;
  final CompanyModel company;

  factory CompanyMembershipModel.fromJson(Map<String, dynamic> json) {
    final companyJson = json['companies'] as Map<String, dynamic>?;

    if (companyJson == null) {
      throw FormatException('Membership response missing companies join');
    }

    return CompanyMembershipModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      company: CompanyModel.fromJson(companyJson),
    );
  }

  CompanyMembership toEntity() {
    return CompanyMembership(
      id: id,
      companyId: companyId,
      role: CompanyRoleDbValue.fromDbValue(role),
      joinedAt: joinedAt,
      company: company.toEntity(),
    );
  }
}
