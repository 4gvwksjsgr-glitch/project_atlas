import '../../../../core/errors/team_error_mapper.dart';
import '../../../../core/permissions/company_role.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/company_invite.dart';
import '../../domain/entities/company_member.dart';
import '../../domain/entities/create_invite_result.dart';
import '../../domain/repositories/company_members_repository.dart';
import '../datasource/company_members_remote_datasource.dart';

class CompanyMembersRepositoryImpl implements CompanyMembersRepository {
  const CompanyMembersRepositoryImpl(this._remoteDataSource);

  final CompanyMembersRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<CompanyMember>>> listMembers(String companyId) async {
    try {
      final members = await _remoteDataSource.listMembers(companyId: companyId);
      return Success(members.map((m) => m.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.listMembers),
      );
    }
  }

  @override
  Future<Result<List<CompanyInvite>>> listInvites(String companyId) async {
    try {
      final invites = await _remoteDataSource.listInvites(companyId: companyId);
      return Success(invites.map((i) => i.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.listInvites),
      );
    }
  }

  @override
  Future<Result<CreateInviteResult>> createInvite(
    String companyId,
    String email,
    CompanyRole role, {
    int? expiresInHours,
  }) async {
    try {
      final result = await _remoteDataSource.createInvite(
        companyId: companyId,
        email: email,
        role: role,
        expiresInHours: expiresInHours,
      );
      return Success(result.toEntity());
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.createInvite),
      );
    }
  }

  @override
  Future<Result<void>> revokeInvite(String inviteId) async {
    try {
      await _remoteDataSource.revokeInvite(inviteId: inviteId);
      return const Success(null);
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.revokeInvite),
      );
    }
  }

  @override
  Future<Result<void>> acceptInvite(String token) async {
    try {
      await _remoteDataSource.acceptInvite(inviteToken: token);
      return const Success(null);
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.acceptInvite),
      );
    }
  }

  @override
  Future<Result<void>> changeMemberRole(
    String companyId,
    String userId,
    CompanyRole role,
  ) async {
    try {
      await _remoteDataSource.changeMemberRole(
        companyId: companyId,
        userId: userId,
        role: role,
      );
      return const Success(null);
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.changeMemberRole),
      );
    }
  }

  @override
  Future<Result<void>> removeMember(String companyId, String userId) async {
    try {
      await _remoteDataSource.removeMember(
        companyId: companyId,
        userId: userId,
      );
      return const Success(null);
    } on Object catch (error) {
      return Error(
        TeamErrorMapper.mapException(error, TeamOperation.removeMember),
      );
    }
  }
}
