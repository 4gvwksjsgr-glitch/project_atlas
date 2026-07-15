import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/usecases/resolve_initial_active_company.dart';

CompanyMembership _membership({
  required String companyId,
  required String name,
  required String slug,
}) {
  return CompanyMembership(
    id: 'membership-$companyId',
    companyId: companyId,
    role: CompanyRole.owner,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: companyId,
      name: name,
      slug: slug,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

void main() {
  group('resolveInitialActiveCompany', () {
    test('zero membership restituisce empty', () {
      expect(
        resolveInitialActiveCompany(memberships: [], persistedCompanyId: null),
        isA<InitialActiveCompanyEmpty>(),
      );
    });

    test('persisted id obsoleto con zero membership restituisce empty', () {
      expect(
        resolveInitialActiveCompany(
          memberships: [],
          persistedCompanyId: 'stale-id',
        ),
        isA<InitialActiveCompanyEmpty>(),
      );
    });

    test('persisted id valido restituisce resolved senza persist', () {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
        _membership(companyId: 'c2', name: 'Beta', slug: 'beta'),
      ];

      final result = resolveInitialActiveCompany(
        memberships: memberships,
        persistedCompanyId: 'c2',
      );

      expect(result, isA<InitialActiveCompanyResolved>());
      final resolved = result as InitialActiveCompanyResolved;
      expect(resolved.context.companyId, 'c2');
      expect(resolved.persistSelection, isFalse);
    });

    test('persisted id obsoleto con una membership auto-select', () {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
      ];

      final result = resolveInitialActiveCompany(
        memberships: memberships,
        persistedCompanyId: 'stale-id',
      );

      expect(result, isA<InitialActiveCompanyResolved>());
      final resolved = result as InitialActiveCompanyResolved;
      expect(resolved.context.companyId, 'c1');
      expect(resolved.persistSelection, isTrue);
    });

    test('persisted id obsoleto con più membership richiede selector', () {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
        _membership(companyId: 'c2', name: 'Beta', slug: 'beta'),
      ];

      final result = resolveInitialActiveCompany(
        memberships: memberships,
        persistedCompanyId: 'stale-id',
      );

      expect(result, isA<InitialActiveCompanyNeedsSelection>());
    });

    test('una sola membership auto-select con persist', () {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
      ];

      final result = resolveInitialActiveCompany(
        memberships: memberships,
        persistedCompanyId: null,
      );

      expect(result, isA<InitialActiveCompanyResolved>());
      final resolved = result as InitialActiveCompanyResolved;
      expect(resolved.persistSelection, isTrue);
    });
  });
}
