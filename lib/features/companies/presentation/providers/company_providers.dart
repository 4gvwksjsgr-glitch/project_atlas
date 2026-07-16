import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/router/user_companies_route_state.dart';
import '../../../../core/storage/app_shared_preferences.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasource/active_company_local_datasource.dart';
import '../../data/datasource/company_remote_datasource.dart';
import '../../data/repositories/active_company_repository_impl.dart';
import '../../data/repositories/company_repository_impl.dart';
import '../../domain/entities/company_membership.dart';
import '../../domain/repositories/active_company_repository.dart';
import '../../domain/repositories/company_repository.dart';
import '../../domain/usecases/create_company.dart';
import '../../domain/usecases/get_user_companies.dart';
import '../../domain/usecases/resolve_initial_active_company.dart';
import '../../domain/usecases/select_active_company.dart';
import '../../domain/usecases/update_company.dart';
import '../controllers/active_company_controller.dart';

final sharedPreferencesProvider = Provider((ref) {
  final preferences = appSharedPreferences;
  if (preferences == null) {
    throw StateError('SharedPreferences non inizializzato');
  }
  return preferences;
});

final activeCompanyLocalDataSourceProvider =
    Provider<ActiveCompanyLocalDataSource>((ref) {
      final preferences = ref.watch(sharedPreferencesProvider);
      return ActiveCompanyLocalDataSource(preferences);
    });

final activeCompanyRepositoryProvider = Provider<ActiveCompanyRepository>((
  ref,
) {
  return ActiveCompanyRepositoryImpl(
    ref.watch(activeCompanyLocalDataSourceProvider),
  );
});

final resolveInitialActiveCompanyUseCaseProvider =
    Provider<ResolveInitialActiveCompany>((ref) {
      return ResolveInitialActiveCompany(
        ref.watch(activeCompanyRepositoryProvider),
      );
    });

final selectActiveCompanyUseCaseProvider = Provider<SelectActiveCompany>((ref) {
  return SelectActiveCompany(ref.watch(activeCompanyRepositoryProvider));
});

final companyRemoteDataSourceProvider = Provider<CompanyRemoteDataSource>((
  ref,
) {
  return CompanyRemoteDataSource(ref.watch(supabaseClientProvider));
});

final companyRepositoryProvider = Provider<CompanyRepository>((ref) {
  return CompanyRepositoryImpl(ref.watch(companyRemoteDataSourceProvider));
});

final createCompanyUseCaseProvider = Provider<CreateCompany>((ref) {
  return CreateCompany(ref.watch(companyRepositoryProvider));
});

final updateCompanyUseCaseProvider = Provider<UpdateCompany>((ref) {
  return UpdateCompany(ref.watch(companyRepositoryProvider));
});

final getUserCompaniesUseCaseProvider = Provider<GetUserCompanies>((ref) {
  return GetUserCompanies(ref.watch(companyRepositoryProvider));
});

final userCompaniesProvider = FutureProvider<List<CompanyMembership>>((
  ref,
) async {
  if (!ref.watch(isAuthenticatedProvider)) {
    return [];
  }

  ref.watch(authStateChangesProvider);

  final result = await ref.read(getUserCompaniesUseCaseProvider).call();
  return result.when(
    success: (memberships) => memberships,
    error: (failure) => throw StateError(failure.message),
  );
});

final userCompaniesRouteStateProvider = Provider<UserCompaniesRouteState>((
  ref,
) {
  if (!ref.watch(isAuthenticatedProvider)) {
    return const UserCompaniesEmpty();
  }

  final companiesAsync = ref.watch(userCompaniesProvider);
  final activeResolved = ref.watch(activeCompanyResolvedProvider);
  final activeCompany = ref.watch(activeCompanyProvider);

  return companiesAsync.when(
    loading: () => const UserCompaniesLoading(),
    data: (memberships) {
      if (memberships.isEmpty) {
        return const UserCompaniesEmpty();
      }
      if (!activeResolved) {
        return const UserCompaniesLoading();
      }
      if (activeCompany != null) {
        return const UserCompaniesReady();
      }
      return const UserCompaniesNeedsSelection();
    },
    error: (error, _) {
      final message = error is StateError
          ? error.message
          : 'Caricamento aziende non riuscito. Riprova.';
      return UserCompaniesError(message);
    },
  );
});
