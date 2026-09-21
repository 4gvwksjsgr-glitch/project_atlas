import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/permissions/company_role.dart';
import '../models/company_invite_model.dart';
import '../models/company_member_model.dart';
import '../models/company_role_mapper.dart';
import '../models/create_invite_result_model.dart';

class CompanyMembersRemoteDataSource {
  CompanyMembersRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<CompanyMemberModel>> listMembers({
    required String companyId,
  }) async {
    final response = await _client.rpc(
      'list_company_members',
      params: {'p_company_id': companyId},
    );
    return _mapList(response, CompanyMemberModel.fromJson);
  }

  Future<List<CompanyInviteModel>> listInvites({
    required String companyId,
  }) async {
    final response = await _client.rpc(
      'list_company_invites',
      params: {'p_company_id': companyId},
    );
    return _mapList(response, CompanyInviteModel.fromJson);
  }

  Future<CreateInviteResultModel> createInvite({
    required String companyId,
    required String email,
    required CompanyRole role,
    int? expiresInHours,
  }) async {
    final params = <String, dynamic>{
      'p_company_id': companyId,
      'p_email': email,
      'p_role': role.toDbValue,
    };
    if (expiresInHours != null) {
      params['p_expires_in_hours'] = expiresInHours;
    }

    final response = await _client.rpc(
      'create_company_invite',
      params: params,
    );
    return CreateInviteResultModel.fromJson(_singleRow(response));
  }

  Future<void> revokeInvite({required String inviteId}) async {
    await _client.rpc(
      'revoke_company_invite',
      params: {'p_invite_id': inviteId},
    );
  }

  Future<void> acceptInvite({required String inviteToken}) async {
    await _client.rpc(
      'accept_company_invite',
      params: {'p_invite_token': inviteToken},
    );
  }

  Future<void> changeMemberRole({
    required String companyId,
    required String userId,
    required CompanyRole role,
  }) async {
    await _client.rpc(
      'change_company_member_role',
      params: {
        'p_company_id': companyId,
        'p_user_id': userId,
        'p_role': role.toDbValue,
      },
    );
  }

  Future<void> removeMember({
    required String companyId,
    required String userId,
  }) async {
    await _client.rpc(
      'remove_company_member',
      params: {
        'p_company_id': companyId,
        'p_user_id': userId,
      },
    );
  }

  static List<T> _mapList<T>(
    Object? response,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (response == null) {
      return const [];
    }
    if (response is! List) {
      throw FormatException('Risposta RPC lista non valida', response);
    }
    return response.map((row) {
      if (row is Map<String, dynamic>) {
        return fromJson(row);
      }
      if (row is Map) {
        return fromJson(Map<String, dynamic>.from(row));
      }
      throw FormatException('Riga RPC non valida', row);
    }).toList();
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    if (response is List) {
      if (response.isEmpty) {
        throw const FormatException('Risposta RPC invite vuota');
      }
      final first = response.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
      throw FormatException('Riga RPC invite non valida', first);
    }
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    throw FormatException('Risposta RPC invite non valida', response);
  }
}
