import '../../domain/entities/create_invite_result.dart';
import 'company_role_mapper.dart';

class CreateInviteResultModel {
  const CreateInviteResultModel({
    required this.inviteId,
    required this.emailNormalized,
    required this.role,
    required this.expiresAt,
    required this.inviteToken,
  });

  final String inviteId;
  final String emailNormalized;
  final String role;
  final DateTime expiresAt;
  final String inviteToken;

  factory CreateInviteResultModel.fromJson(Map<String, dynamic> json) {
    return CreateInviteResultModel(
      inviteId: json['invite_id'] as String,
      emailNormalized: json['email_normalized'] as String,
      role: json['role'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      inviteToken: json['invite_token'] as String,
    );
  }

  CreateInviteResult toEntity() {
    return CreateInviteResult(
      inviteId: inviteId,
      emailNormalized: emailNormalized,
      role: CompanyRoleDbValue.fromDbValue(role),
      expiresAt: expiresAt,
      inviteToken: inviteToken,
    );
  }
}
