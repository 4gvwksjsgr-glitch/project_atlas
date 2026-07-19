import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/dashboard_cash_remote_datasource.dart';
import '../../data/repositories/dashboard_cash_repository_impl.dart';
import '../../domain/entities/dashboard_cash_summary.dart';
import '../../domain/repositories/dashboard_cash_repository.dart';
import '../../domain/usecases/get_dashboard_cash_summary.dart';

final dashboardCashRemoteDataSourceProvider =
    Provider<DashboardCashRemoteDataSource>((ref) {
      return SupabaseDashboardCashRemoteDataSource(
        ref.watch(supabaseClientProvider),
      );
    });

final dashboardCashRepositoryProvider = Provider<DashboardCashRepository>((
  ref,
) {
  return DashboardCashRepositoryImpl(
    ref.watch(dashboardCashRemoteDataSourceProvider),
  );
});

final getDashboardCashSummaryUseCaseProvider =
    Provider<GetDashboardCashSummary>((ref) {
      return GetDashboardCashSummary(
        ref.watch(dashboardCashRepositoryProvider),
      );
    });

/// Riepilogo economico keyed per azienda: al cambio companyId nuova query.
final dashboardCashSummaryProvider = FutureProvider.autoDispose
    .family<DashboardCashSummary, String>((ref, companyId) async {
      final result = await ref
          .read(getDashboardCashSummaryUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (summary) => summary,
        error: (failure) => throw StateError(failure.message),
      );
    });
