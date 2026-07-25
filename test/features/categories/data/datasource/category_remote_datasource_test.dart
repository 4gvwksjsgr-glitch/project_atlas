import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/categories/data/datasource/category_remote_datasource.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';

void main() {
  group('CategoryRemoteDataSource', () {
    test('lista filtra sempre per company_id', () async {
      String? seenCompanyId;
      final ds = CategoryRemoteDataSource.test(
        listExecutor: ({required companyId}) async {
          seenCompanyId = companyId;
          return [
            {
              'id': 'cat-1',
              'company_id': companyId,
              'name': 'Software',
              'kind': 'expense',
              'is_active': true,
              'created_at': '2026-07-24T10:00:00.000Z',
              'updated_at': '2026-07-24T10:00:00.000Z',
            },
          ];
        },
      );

      final rows = await ds.getCategories(companyId: 'c1');
      expect(seenCompanyId, 'c1');
      expect(rows.single.companyId, 'c1');
    });

    test('rifiuta companyId vuoto sulla lista', () async {
      final ds = CategoryRemoteDataSource.test(
        listExecutor: ({required companyId}) async => [],
      );
      expect(
        () => ds.getCategories(companyId: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('create include company_id, name, kind e is_active true', () async {
      Map<String, dynamic>? seen;
      final ds = CategoryRemoteDataSource.test(
        createExecutor:
            ({required companyId, required name, required kind}) async {
              seen = {'companyId': companyId, 'name': name, 'kind': kind};
              return {
                'id': 'cat-1',
                'company_id': companyId,
                'name': name,
                'kind': kind.dbValue,
                'is_active': true,
                'created_at': '2026-07-24T10:00:00.000Z',
                'updated_at': '2026-07-24T10:00:00.000Z',
              };
            },
      );

      await ds.createCategory(
        companyId: 'c1',
        name: 'Software',
        kind: TransactionKind.expense,
      );
      expect(seen?['companyId'], 'c1');
      expect(seen?['name'], 'Software');
      expect(seen?['kind'], TransactionKind.expense);
    });

    test('payload INSERT contiene solo colonne least-privilege', () {
      final payload = CategoryRemoteDataSource.buildCreatePayload(
        companyId: 'c1',
        name: 'Software',
        kind: TransactionKind.expense,
      );

      expect(payload.keys.toSet(), {'company_id', 'name', 'kind', 'is_active'});
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('created_at'), isFalse);
      expect(payload.containsKey('updated_at'), isFalse);
      expect(payload['company_id'], 'c1');
      expect(payload['name'], 'Software');
      expect(payload['kind'], 'expense');
      expect(payload['is_active'], isTrue);
    });

    test('rename e setActive usano company_id + categoryId', () async {
      String? renameCompany;
      String? renameId;
      String? activeCompany;
      String? activeId;
      bool? activeValue;

      final ds = CategoryRemoteDataSource.test(
        renameExecutor:
            ({required companyId, required categoryId, required name}) async {
              renameCompany = companyId;
              renameId = categoryId;
              return {
                'id': categoryId,
                'company_id': companyId,
                'name': name,
                'kind': 'expense',
                'is_active': true,
                'created_at': '2026-07-24T10:00:00.000Z',
                'updated_at': '2026-07-24T10:00:00.000Z',
              };
            },
        setActiveExecutor:
            ({
              required companyId,
              required categoryId,
              required isActive,
            }) async {
              activeCompany = companyId;
              activeId = categoryId;
              activeValue = isActive;
              return {
                'id': categoryId,
                'company_id': companyId,
                'name': 'Software',
                'kind': 'expense',
                'is_active': isActive,
                'created_at': '2026-07-24T10:00:00.000Z',
                'updated_at': '2026-07-24T10:00:00.000Z',
              };
            },
      );

      await ds.renameCategory(
        companyId: 'c1',
        categoryId: 'cat-1',
        name: 'Licenze',
      );
      await ds.setCategoryActive(
        companyId: 'c1',
        categoryId: 'cat-1',
        isActive: false,
      );

      expect(renameCompany, 'c1');
      expect(renameId, 'cat-1');
      expect(activeCompany, 'c1');
      expect(activeId, 'cat-1');
      expect(activeValue, isFalse);
    });
  });
}
