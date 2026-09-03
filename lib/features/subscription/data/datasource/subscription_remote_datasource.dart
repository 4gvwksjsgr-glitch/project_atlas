import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_subscription_overview_model.dart';
import '../models/premium_checkout_session_model.dart';

typedef SubscriptionFunctionsInvoker =
    Future<FunctionResponse> Function(
      String functionName, {
      Map<String, String>? headers,
      Object? body,
    });

class SubscriptionRemoteDataSource {
  SubscriptionRemoteDataSource(
    this._client, {
    SubscriptionFunctionsInvoker? functionsInvoker,
  }) : _functionsInvoker =
           functionsInvoker ??
           ((functionName, {headers, body}) {
             return _client.functions.invoke(
               functionName,
               headers: headers,
               body: body,
             );
           });

  final SupabaseClient _client;
  final SubscriptionFunctionsInvoker _functionsInvoker;

  static const checkoutCreateFunctionName = 'billing-checkout-create';

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

  Future<void> activateCompanyPremiumTrial({required String companyId}) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    await _client.rpc(
      'activate_company_premium_trial',
      params: {'p_company_id': companyId},
    );
  }

  Future<PremiumCheckoutSessionModel> createCompanyPremiumCheckout({
    required String companyId,
    required String idempotencyKey,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    if (idempotencyKey.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'obbligatorio',
      );
    }

    final response = await _functionsInvoker(
      checkoutCreateFunctionName,
      headers: {'Idempotency-Key': idempotencyKey},
      body: {'company_id': companyId},
    );

    final data = response.data;
    if (data is! Map) {
      throw const FormatException(
        'Risposta billing-checkout-create non valida',
      );
    }

    return PremiumCheckoutSessionModel.fromJson(
      Map<String, dynamic>.from(data),
    );
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
