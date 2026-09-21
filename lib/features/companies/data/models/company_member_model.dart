import '../../domain/entities/company_member.dart';
import 'company_role_mapper.dart';

class CompanyMemberModel {
  const CompanyMemberModel({
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
  final String role;
  final DateTime joinedAt;

  factory CompanyMemberModel.fromJson(Map<String, dynamic> json) {
    return CompanyMemberModel(
      membershipId: json['membership_id'] as String,
      userId: json['user_id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  CompanyMember toEntity() {
    return CompanyMember(
      membershipId: membershipId,
      userId: userId,
      email: email,
      fullName: fullName,
      role: CompanyRoleDbValue.fromDbValue(role),
      joinedAt: joinedAt,
    );
  }
}
