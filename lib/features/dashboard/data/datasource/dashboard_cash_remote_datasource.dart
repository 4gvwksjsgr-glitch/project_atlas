import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../transactions/domain/value_objects/calendar_date.dart';
import '../models/dashboard_cash_summary_model.dart';

abstract class DashboardCashRemoteDataSource {
  Future<DashboardCashSummaryModel> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  });
}

class SupabaseDashboardCashRemoteDataSource
    implements DashboardCashRemoteDataSource {
  const SupabaseDashboardCashRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<DashboardCashSummaryModel> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }

    final response = await _client.rpc(
      'get_company_cash_summary',
      params: {
        'p_company_id': companyId,
        'p_month_start': CalendarDate.toIsoDate(monthStart),
        'p_next_month_start': CalendarDate.toIsoDate(nextMonthStart),
      },
    );

    final row = _singleRow(response);
    return DashboardCashSummaryModel.fromJson(row);
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    if (response is List) {
      if (response.isEmpty) {
        throw const FormatException('Risposta RPC cash summary vuota');
      }
      final first = response.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
      throw FormatException('Riga RPC cash summary non valida', first);
    }

    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    throw FormatException('Risposta RPC cash summary non valida', response);
  }
}
