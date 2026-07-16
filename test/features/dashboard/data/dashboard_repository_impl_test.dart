import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/features/dashboard/data/datasource/dashboard_remote_datasource.dart';
import 'package:project_atlas/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_summary.dart';

class _FakeDashboardRemoteDataSource implements DashboardRemoteDataSource {
  _FakeDashboardRemoteDataSource({this.count = 4});

  final int count;
  String? lastCompanyId;

  @override
  Future<int> countCompanyMembers({required String companyId}) async {
    lastCompanyId = companyId;
    if (companyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'obbligatorio');
    }
    return count;
  }
}

void main() {
  group('DashboardRemoteDataSource contract', () {
    test('rifiuta companyId vuoto', () async {
      final dataSource = _FakeDashboardRemoteDataSource();

      expect(
        () => dataSource.countCompanyMembers(companyId: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('inoltra companyId usato come filtro company_id', () async {
      final dataSource = _FakeDashboardRemoteDataSource();

      await dataSource.countCompanyMembers(companyId: 'company-42');

      expect(dataSource.lastCompanyId, 'company-42');
    });
  });

  group('SupabaseDashboardRemoteDataSource', () {
    test('query count filtra company_members per company_id', () async {
      final source = await File(
        'lib/features/dashboard/data/datasource/dashboard_remote_datasource.dart',
      ).readAsString();

      expect(source.contains(".from('company_members')"), isTrue);
      expect(source.contains('.count(CountOption.exact)'), isTrue);
      expect(source.contains(".eq('company_id', companyId)"), isTrue);
      expect(source.contains('.select('), isFalse);
    });
  });

  group('DashboardRepositoryImpl', () {
    test('mappa il conteggio in DashboardSummary', () async {
      final dataSource = _FakeDashboardRemoteDataSource(count: 7);
      final repository = DashboardRepositoryImpl(dataSource);

      final result = await repository.getSummary(companyId: 'company-7');

      expect(dataSource.lastCompanyId, 'company-7');
      expect(
        result.when(success: (value) => value, error: (_) => null),
        isA<DashboardSummary>().having((s) => s.memberCount, 'memberCount', 7),
      );
    });

    test(
      'companyId vuoto restituisce ValidationFailure senza chiamare DS',
      () async {
        final dataSource = _FakeDashboardRemoteDataSource();
        final repository = DashboardRepositoryImpl(dataSource);

        final result = await repository.getSummary(companyId: '');

        expect(
          result.when(success: (_) => null, error: (failure) => failure),
          isA<ValidationFailure>(),
        );
        expect(dataSource.lastCompanyId, isNull);
      },
    );
  });
}
