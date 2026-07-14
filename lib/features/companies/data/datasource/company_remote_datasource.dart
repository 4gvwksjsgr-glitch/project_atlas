import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_membership_model.dart';
import '../models/company_model.dart';

class CompanyRemoteDataSource {
  const CompanyRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CompanyModel> createCompany({
    required String name,
    required String slug,
  }) async {
    final response = await _client.rpc(
      'create_company',
      params: {'p_name': name, 'p_slug': slug},
    );

    return CompanyModel.fromJson(response as Map<String, dynamic>);
  }

  Future<List<CompanyMembershipModel>> getUserCompanies() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    final response = await _client
        .from('company_members')
        .select(
          'id, company_id, role, joined_at, companies(id, name, slug, created_at, updated_at)',
        )
        .eq('user_id', userId)
        .order('joined_at');

    return (response as List<dynamic>)
        .map(
          (row) => CompanyMembershipModel.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }
}
