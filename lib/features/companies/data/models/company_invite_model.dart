import '../../domain/entities/company_invite.dart';
import 'company_role_mapper.dart';

class CompanyInviteModel {
  const CompanyInviteModel({
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
  final String role;
  final String invitedBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final String status;

  factory CompanyInviteModel.fromJson(Map<String, dynamic> json) {
    return CompanyInviteModel(
      inviteId: json['invite_id'] as String,
      emailNormalized: json['email_normalized'] as String,
      role: json['role'] as String,
      invitedBy: json['invited_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      acceptedAt: _parseOptionalDate(json['accepted_at']),
      revokedAt: _parseOptionalDate(json['revoked_at']),
      status: json['status'] as String,
    );
  }

  CompanyInvite toEntity() {
    return CompanyInvite(
      inviteId: inviteId,
      emailNormalized: emailNormalized,
      role: CompanyRoleDbValue.fromDbValue(role),
      invitedBy: invitedBy,
      createdAt: createdAt,
      expiresAt: expiresAt,
      acceptedAt: acceptedAt,
      revokedAt: revokedAt,
      status: _parseStatus(status),
    );
  }

  static DateTime? _parseOptionalDate(Object? value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value);
    }
    return null;
  }

  static CompanyInviteStatus _parseStatus(String value) {
    return CompanyInviteStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => CompanyInviteStatus.pending,
    );
  }
}
