import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/active_company_context.dart';
import '../../domain/entities/company_membership.dart';
import '../providers/company_providers.dart';
import 'active_company_state.dart';

class ActiveCompanyController extends Notifier<ActiveCompanyState> {
  @override
  ActiveCompanyState build() {
    return const ActiveCompanyState();
  }

  void markResolving() {
    state = state.copyWith(clearContext: true, resolved: false);
  }

  void applyResolution({
    required ActiveCompanyContext? context,
    required bool resolved,
  }) {
    state = ActiveCompanyState(context: context, resolved: resolved);
  }

  Future<void> selectMembership({
    required String userId,
    required CompanyMembership membership,
  }) async {
    final context = await ref
        .read(selectActiveCompanyUseCaseProvider)
        .call(userId: userId, membership: membership);
    state = ActiveCompanyState(context: context, resolved: true);
  }

  Future<void> selectByCompanyId(String companyId) async {
    final userId = ref.read(authSessionProvider)?.user.id;
    if (userId == null) {
      return;
    }

    final memberships = await ref.read(userCompaniesProvider.future);
    final membership = memberships.firstWhere(
      (entry) => entry.companyId == companyId,
    );
    await selectMembership(userId: userId, membership: membership);
  }

  void clearRuntime() {
    state = const ActiveCompanyState(resolved: true);
  }
}

final activeCompanyControllerProvider =
    NotifierProvider<ActiveCompanyController, ActiveCompanyState>(
      ActiveCompanyController.new,
    );

final activeCompanyProvider = Provider<ActiveCompanyContext?>((ref) {
  return ref.watch(activeCompanyControllerProvider).context;
});

final activeCompanyResolvedProvider = Provider<bool>((ref) {
  return ref.watch(activeCompanyControllerProvider).resolved;
});
