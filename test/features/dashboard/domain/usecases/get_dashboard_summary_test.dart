import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:project_atlas/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:project_atlas/features/dashboard/domain/usecases/get_dashboard_summary.dart';

class _FakeDashboardRepository implements DashboardRepository {
  String? lastCompanyId;

  @override
  Future<Result<DashboardSummary>> getSummary({
    required String companyId,
  }) async {
    lastCompanyId = companyId;
    return const Success(DashboardSummary(memberCount: 3));
  }
}

void main() {
  group('GetDashboardSummary', () {
    test('inoltra esattamente il companyId al repository', () async {
      final repository = _FakeDashboardRepository();
      final useCase = GetDashboardSummary(repository);

      final result = await useCase.call(companyId: 'company-abc');

      expect(repository.lastCompanyId, 'company-abc');
      expect(
        result.when(success: (value) => value.memberCount, error: (_) => -1),
        3,
      );
    });
  });
}
