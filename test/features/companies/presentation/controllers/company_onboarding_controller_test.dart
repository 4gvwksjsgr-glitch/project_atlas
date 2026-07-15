import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/create_company.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../test_helpers/shared_preferences_test_helper.dart';

class _SuccessCreateCompanyRepository implements CompanyRepository {
  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    return Success(
      Company(
        id: 'company-1',
        name: name,
        slug: slug,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();
}

Session _testSession({String userId = 'user-1'}) {
  return Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026).toIso8601String(),
    ),
  );
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('CompanyOnboardingController', () {
    test(
      'refresh membership fallito imposta error e non resta in loading',
      () async {
        final container = ProviderContainer(
          overrides: [
            createCompanyUseCaseProvider.overrideWithValue(
              CreateCompany(_SuccessCreateCompanyRepository()),
            ),
            userCompaniesProvider.overrideWith(
              (ref) async => throw StateError(
                'Caricamento aziende non riuscito. Riprova.',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          companyOnboardingControllerProvider.notifier,
        );

        await notifier.createCompany(name: 'Acme Corp', slug: 'acme-corp');

        final state = container.read(companyOnboardingControllerProvider);
        expect(state.actionStatus, CompanyActionStatus.error);
        expect(state.isLoading, isFalse);
        expect(
          state.errorMessage,
          'Caricamento aziende non riuscito. Riprova.',
        );
      },
    );

    test('refresh membership riuscito imposta success', () async {
      final company = Company(
        id: 'company-1',
        name: 'Acme Corp',
        slug: 'acme-corp',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final container = ProviderContainer(
        overrides: [
          createCompanyUseCaseProvider.overrideWithValue(
            CreateCompany(_SuccessCreateCompanyRepository()),
          ),
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          userCompaniesProvider.overrideWith(
            (ref) async => [
              CompanyMembership(
                id: 'membership-1',
                companyId: company.id,
                role: CompanyRole.owner,
                joinedAt: DateTime.utc(2026, 1, 1),
                company: company,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        companyOnboardingControllerProvider.notifier,
      );

      await notifier.createCompany(name: 'Acme Corp', slug: 'acme-corp');

      final state = container.read(companyOnboardingControllerProvider);
      expect(state.actionStatus, CompanyActionStatus.success);
      expect(state.isLoading, isFalse);
      expect(state.createdCompany?.slug, 'acme-corp');
    });
  });
}
