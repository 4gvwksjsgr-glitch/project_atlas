import 'package:supabase_flutter/supabase_flutter.dart';

abstract class DashboardRemoteDataSource {
  Future<int> countCompanyMembers({required String companyId});
}

class SupabaseDashboardRemoteDataSource implements DashboardRemoteDataSource {
  const SupabaseDashboardRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// Conta i membri di [companyId] senza scaricare le righe.
  @override
  Future<int> countCompanyMembers({required String companyId}) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    return _client
        .from('company_members')
        .count(CountOption.exact)
        .eq('company_id', companyId);
  }
}
