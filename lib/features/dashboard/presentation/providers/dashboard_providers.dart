import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/dashboard_remote_datasource.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/usecases/get_dashboard_summary.dart';

final dashboardRemoteDataSourceProvider = Provider<DashboardRemoteDataSource>((
  ref,
) {
  return SupabaseDashboardRemoteDataSource(ref.watch(supabaseClientProvider));
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(ref.watch(dashboardRemoteDataSourceProvider));
});

final getDashboardSummaryUseCaseProvider = Provider<GetDashboardSummary>((ref) {
  return GetDashboardSummary(ref.watch(dashboardRepositoryProvider));
});

/// Summary keyed per azienda attiva: al cambio companyId parte una nuova query.
final dashboardSummaryProvider = FutureProvider.autoDispose
    .family<DashboardSummary, String>((ref, companyId) async {
      final result = await ref
          .read(getDashboardSummaryUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (summary) => summary,
        error: (failure) => throw StateError(failure.message),
      );
    });
