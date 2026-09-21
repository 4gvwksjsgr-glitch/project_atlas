import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/router/user_companies_route_state.dart';
import '../../../../core/storage/app_shared_preferences.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasource/active_company_local_datasource.dart';
import '../../data/datasource/company_members_remote_datasource.dart';
import '../../data/datasource/company_remote_datasource.dart';
import '../../data/repositories/active_company_repository_impl.dart';
import '../../data/repositories/company_members_repository_impl.dart';
import '../../data/repositories/company_repository_impl.dart';
import '../../domain/entities/company_membership.dart';
import '../../domain/repositories/active_company_repository.dart';
import '../../domain/repositories/company_members_repository.dart';
import '../../domain/repositories/company_repository.dart';
import '../../domain/usecases/accept_company_invite.dart';
import '../../domain/usecases/change_company_member_role.dart';
import '../../domain/usecases/create_company.dart';
import '../../domain/usecases/create_company_invite.dart';
import '../../domain/usecases/get_user_companies.dart';
import '../../domain/usecases/list_company_invites.dart';
import '../../domain/usecases/list_company_members.dart';
import '../../domain/usecases/remove_company_member.dart';
import '../../domain/usecases/resolve_initial_active_company.dart';
import '../../domain/usecases/revoke_company_invite.dart';
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

final companyMembersRemoteDataSourceProvider =
    Provider<CompanyMembersRemoteDataSource>((ref) {
      return CompanyMembersRemoteDataSource(ref.watch(supabaseClientProvider));
    });

final companyMembersRepositoryProvider = Provider<CompanyMembersRepository>((
  ref,
) {
  return CompanyMembersRepositoryImpl(
    ref.watch(companyMembersRemoteDataSourceProvider),
  );
});

final listCompanyMembersUseCaseProvider = Provider<ListCompanyMembers>((ref) {
  return ListCompanyMembers(ref.watch(companyMembersRepositoryProvider));
});

final listCompanyInvitesUseCaseProvider = Provider<ListCompanyInvites>((ref) {
  return ListCompanyInvites(ref.watch(companyMembersRepositoryProvider));
});

final createCompanyInviteUseCaseProvider = Provider<CreateCompanyInvite>((ref) {
  return CreateCompanyInvite(ref.watch(companyMembersRepositoryProvider));
});

final revokeCompanyInviteUseCaseProvider = Provider<RevokeCompanyInvite>((ref) {
  return RevokeCompanyInvite(ref.watch(companyMembersRepositoryProvider));
});

final acceptCompanyInviteUseCaseProvider = Provider<AcceptCompanyInvite>((ref) {
  return AcceptCompanyInvite(ref.watch(companyMembersRepositoryProvider));
});

final changeCompanyMemberRoleUseCaseProvider =
    Provider<ChangeCompanyMemberRole>((ref) {
      return ChangeCompanyMemberRole(
        ref.watch(companyMembersRepositoryProvider),
      );
    });

final removeCompanyMemberUseCaseProvider = Provider<RemoveCompanyMember>((ref) {
  return RemoveCompanyMember(ref.watch(companyMembersRepositoryProvider));
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
