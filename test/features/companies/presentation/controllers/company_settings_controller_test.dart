import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/update_company.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_settings_controller.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';

class _UpdateCompanyRepository implements CompanyRepository {
  _UpdateCompanyRepository({this.result, this.gate});

  Result<Company>? result;
  final Completer<void>? gate;
  String? lastCompanyId;
  String? lastName;
  String? lastSlug;
  int callCount = 0;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) => throw UnimplementedError();

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) async {
    callCount += 1;
    lastCompanyId = companyId;
    lastName = name;
    lastSlug = slug;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    return result ??
        Success(
          Company(
            id: companyId,
            name: name,
            slug: slug,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        );
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() async {
    return Success([
      CompanyMembership(
        id: 'membership-1',
        companyId: 'company-1',
        role: CompanyRole.owner,
        joinedAt: DateTime.utc(2026, 1, 1),
        company: Company(
          id: 'company-1',
          name: lastName ?? 'Acme',
          slug: lastSlug ?? 'acme',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ),
    ]);
  }
}

ActiveCompanyContext _context({
  CompanyRole role = CompanyRole.owner,
  String companyId = 'company-1',
  String name = 'Acme',
  String slug = 'acme',
}) {
  return ActiveCompanyContext(
    companyId: companyId,
    companyName: name,
    companySlug: slug,
    role: role,
    membershipId: 'membership-1',
  );
}

ProviderContainer _container({
  required CompanyRole role,
  required _UpdateCompanyRepository repository,
  ActiveCompanyContext? context,
}) {
  final active = context ?? _context(role: role);
  final container = ProviderContainer(
    overrides: [
      updateCompanyUseCaseProvider.overrideWithValue(UpdateCompany(repository)),
      companyRepositoryProvider.overrideWithValue(repository),
      userCompaniesProvider.overrideWith(
        (ref) => repository.getUserCompanies().then(
          (result) => result.when(
            success: (value) => value,
            error: (failure) => throw StateError(failure.message),
          ),
        ),
      ),
    ],
  );

  container
      .read(activeCompanyControllerProvider.notifier)
      .applyResolution(context: active, resolved: true);

  return container;
}

void main() {
  group('CompanySettingsController', () {
    test('owner può salvare e aggiorna ActiveCompanyContext', () async {
      final repository = _UpdateCompanyRepository();
      final container = _container(
        role: CompanyRole.owner,
        repository: repository,
      );
      addTearDown(container.dispose);

      await container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'Nuovo Nome', slug: 'nuovo-slug');

      final state = container.read(
        companySettingsControllerProvider('company-1'),
      );
      expect(state.actionStatus, CompanyActionStatus.success);
      expect(repository.callCount, 1);
      expect(repository.lastCompanyId, 'company-1');

      final active = container.read(activeCompanyProvider);
      expect(active?.companyName, 'Nuovo Nome');
      expect(active?.companySlug, 'nuovo-slug');
      expect(active?.companyId, 'company-1');
      expect(active?.role, CompanyRole.owner);
      expect(active?.membershipId, 'membership-1');
    });

    test('admin può salvare', () async {
      final repository = _UpdateCompanyRepository();
      final container = _container(
        role: CompanyRole.admin,
        repository: repository,
      );
      addTearDown(container.dispose);

      await container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'Admin Co', slug: 'admin-co');

      expect(
        container
            .read(companySettingsControllerProvider('company-1'))
            .actionStatus,
        CompanyActionStatus.success,
      );
      expect(repository.callCount, 1);
    });

    test('manager non può salvare', () async {
      final repository = _UpdateCompanyRepository();
      final container = _container(
        role: CompanyRole.manager,
        repository: repository,
      );
      addTearDown(container.dispose);

      await container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'X', slug: 'x');

      final state = container.read(
        companySettingsControllerProvider('company-1'),
      );
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.errorMessage, contains('permessi'));
      expect(repository.callCount, 0);
    });

    test('employee non può salvare', () async {
      final repository = _UpdateCompanyRepository();
      final container = _container(
        role: CompanyRole.employee,
        repository: repository,
      );
      addTearDown(container.dispose);

      await container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'X', slug: 'x');

      expect(repository.callCount, 0);
      expect(
        container
            .read(companySettingsControllerProvider('company-1'))
            .actionStatus,
        CompanyActionStatus.error,
      );
    });

    test('errore conserva lo stato di errore senza successo', () async {
      final repository = _UpdateCompanyRepository(
        result: const Error(
          ValidationFailure('Questo slug è già in uso. Scegline un altro.'),
        ),
      );
      final container = _container(
        role: CompanyRole.owner,
        repository: repository,
      );
      addTearDown(container.dispose);

      await container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'Acme', slug: 'taken');

      final state = container.read(
        companySettingsControllerProvider('company-1'),
      );
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.errorMessage, contains('slug'));
      expect(container.read(activeCompanyProvider)?.companyName, 'Acme');
    });

    test('durante il salvataggio isLoading è true', () async {
      final gate = Completer<void>();
      final repository = _UpdateCompanyRepository(gate: gate);
      final container = _container(
        role: CompanyRole.owner,
        repository: repository,
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        companySettingsControllerProvider('company-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      final future = container
          .read(companySettingsControllerProvider('company-1').notifier)
          .save(name: 'Nuovo', slug: 'nuovo');

      expect(
        container
            .read(companySettingsControllerProvider('company-1'))
            .isLoading,
        isTrue,
      );

      gate.complete();
      await future;
      expect(
        container
            .read(companySettingsControllerProvider('company-1'))
            .isLoading,
        isFalse,
      );
    });
  });
}
