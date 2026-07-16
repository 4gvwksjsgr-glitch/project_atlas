import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_membership_model.dart';
import '../models/company_model.dart';

/// Esegue l'UPDATE su `companies` limitato a un `companyId`.
typedef CompanyUpdateExecutor =
    Future<Map<String, dynamic>> Function({
      required String companyId,
      required String name,
      required String slug,
    });

class CompanyRemoteDataSource {
  CompanyRemoteDataSource(
    SupabaseClient client, {
    @visibleForTesting this._updateExecutor,
  }) : _client = client;

  /// Costruttore di test: nessun client Supabase, solo executor iniettabile.
  @visibleForTesting
  CompanyRemoteDataSource.test({required this._updateExecutor})
    : _client = null;

  final SupabaseClient? _client;
  final CompanyUpdateExecutor? _updateExecutor;

  static const updateSelectColumns = 'id, name, slug, created_at, updated_at';

  Future<CompanyModel> createCompany({
    required String name,
    required String slug,
  }) async {
    final response = await _client!.rpc(
      'create_company',
      params: {'p_name': name, 'p_slug': slug},
    );

    return CompanyModel.fromJson(response as Map<String, dynamic>);
  }

  Future<List<CompanyMembershipModel>> getUserCompanies() async {
    final userId = _client!.auth.currentUser?.id;
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

  Future<CompanyModel> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final executor = _updateExecutor ?? _executeUpdate;
    final response = await executor(
      companyId: companyId,
      name: name,
      slug: slug,
    );

    return CompanyModel.fromJson(response);
  }

  /// UPDATE diretto sempre filtrato con `.eq('id', companyId)`.
  Future<Map<String, dynamic>> _executeUpdate({
    required String companyId,
    required String name,
    required String slug,
  }) async {
    return await _client!
        .from('companies')
        .update({'name': name, 'slug': slug})
        .eq('id', companyId)
        .select(updateSelectColumns)
        .single();
  }
}
