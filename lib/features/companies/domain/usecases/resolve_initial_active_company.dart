import '../entities/active_company_context.dart';
import '../entities/company_membership.dart';
import '../repositories/active_company_repository.dart';

sealed class InitialActiveCompanyResolution {
  const InitialActiveCompanyResolution();
}

final class InitialActiveCompanyResolved
    extends InitialActiveCompanyResolution {
  const InitialActiveCompanyResolved(
    this.context, {
    this.persistSelection = false,
  });

  final ActiveCompanyContext context;
  final bool persistSelection;
}

final class InitialActiveCompanyNeedsSelection
    extends InitialActiveCompanyResolution {
  const InitialActiveCompanyNeedsSelection();
}

final class InitialActiveCompanyEmpty extends InitialActiveCompanyResolution {
  const InitialActiveCompanyEmpty();
}

ActiveCompanyContext activeCompanyContextFromMembership(
  CompanyMembership membership,
) {
  return ActiveCompanyContext(
    companyId: membership.companyId,
    companyName: membership.company.name,
    companySlug: membership.company.slug,
    role: membership.role,
    membershipId: membership.id,
  );
}

InitialActiveCompanyResolution resolveInitialActiveCompany({
  required List<CompanyMembership> memberships,
  required String? persistedCompanyId,
}) {
  if (memberships.isEmpty) {
    return const InitialActiveCompanyEmpty();
  }

  if (persistedCompanyId != null) {
    for (final membership in memberships) {
      if (membership.companyId == persistedCompanyId) {
        return InitialActiveCompanyResolved(
          activeCompanyContextFromMembership(membership),
        );
      }
    }
  }

  if (memberships.length == 1) {
    return InitialActiveCompanyResolved(
      activeCompanyContextFromMembership(memberships.first),
      persistSelection: true,
    );
  }

  return const InitialActiveCompanyNeedsSelection();
}

class ResolveInitialActiveCompany {
  const ResolveInitialActiveCompany(this._repository);

  final ActiveCompanyRepository _repository;

  Future<InitialActiveCompanyResolution> call({
    required String userId,
    required List<CompanyMembership> memberships,
  }) async {
    var persistedCompanyId = await _repository.getPersistedCompanyId(userId);

    if (persistedCompanyId != null) {
      final isPersistedIdValid = memberships.any(
        (membership) => membership.companyId == persistedCompanyId,
      );
      if (!isPersistedIdValid) {
        await _repository.clearPersistedCompanyId(userId);
        persistedCompanyId = null;
      }
    }

    return resolveInitialActiveCompany(
      memberships: memberships,
      persistedCompanyId: persistedCompanyId,
    );
  }
}
