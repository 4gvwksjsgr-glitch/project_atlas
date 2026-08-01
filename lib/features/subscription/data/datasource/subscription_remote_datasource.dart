import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_subscription_overview_model.dart';

class SubscriptionRemoteDataSource {
  SubscriptionRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CompanySubscriptionOverviewModel> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final response = await _client.rpc(
      'get_company_subscription_overview',
      params: {'p_company_id': companyId},
    );

    final row = _singleRow(response);
    return CompanySubscriptionOverviewModel.fromJson(row);
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    if (response is List) {
      if (response.isEmpty) {
        throw const FormatException('Risposta RPC subscription vuota');
      }
      final first = response.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
      throw FormatException('Riga RPC subscription non valida', first);
    }

    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    throw FormatException('Risposta RPC subscription non valida', response);
  }
}
