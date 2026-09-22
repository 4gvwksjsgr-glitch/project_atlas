import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/referral_overview_model.dart';

class ReferralRemoteDataSource {
  ReferralRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<ReferralLinkModel> getOrCreateCompanyReferralLink({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final response = await _client.rpc(
      'get_or_create_company_referral_link',
      params: {'p_company_id': companyId},
    );

    return ReferralLinkModel.fromJson(_singleRow(response));
  }

  Future<ReferralLinkModel> regenerateCompanyReferralLink({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final response = await _client.rpc(
      'regenerate_company_referral_link',
      params: {'p_company_id': companyId},
    );

    return ReferralLinkModel.fromJson(_singleRow(response));
  }

  Future<ClaimReferralResultModel> claimReferral({required String code}) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'code', 'obbligatorio');
    }

    final response = await _client.rpc(
      'claim_referral',
      params: {'p_code': trimmed},
    );

    return ClaimReferralResultModel.fromJson(_singleRow(response));
  }

  Future<ReferralOverviewModel> getReferralOverview({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final response = await _client.rpc(
      'get_referral_overview',
      params: {'p_company_id': companyId},
    );

    return ReferralOverviewModel.fromJson(_singleRow(response));
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    if (response is List) {
      if (response.isEmpty) {
        throw const FormatException('Risposta RPC referral vuota');
      }
      final first = response.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
      throw FormatException('Riga RPC referral non valida', first);
    }

    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    throw FormatException('Risposta RPC referral non valida', response);
  }
}
