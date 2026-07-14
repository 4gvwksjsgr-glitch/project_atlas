import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/router/user_companies_route_state.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasource/company_remote_datasource.dart';
import '../../data/repositories/company_repository_impl.dart';
import '../../domain/entities/company_membership.dart';
import '../../domain/repositories/company_repository.dart';
import '../../domain/usecases/create_company.dart';
import '../../domain/usecases/get_user_companies.dart';

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
  return companiesAsync.when(
    loading: () => const UserCompaniesLoading(),
    data: (memberships) => memberships.isEmpty
        ? const UserCompaniesEmpty()
        : const UserCompaniesAvailable(),
    error: (error, _) {
      final message = error is StateError
          ? error.message
          : 'Caricamento aziende non riuscito. Riprova.';
      return UserCompaniesError(message);
    },
  );
});
