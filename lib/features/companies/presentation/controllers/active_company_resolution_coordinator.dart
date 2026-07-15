import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/active_company_context.dart';
import '../../domain/entities/company_membership.dart';
import '../../domain/usecases/resolve_initial_active_company.dart';
import '../providers/company_providers.dart';
import 'active_company_controller.dart';
import 'active_company_state.dart';

String _resolutionKey(String? userId, List<CompanyMembership> memberships) {
  final companyIds = memberships
      .map((membership) => membership.companyId)
      .join('|');
  return '${userId ?? ''}#$companyIds';
}

class _ResolutionTracker {
  String? lastResolvedKey;
  int generation = 0;
}

/// Coordina la risoluzione dell'azienda attiva fuori dal build dei provider derivati.
final activeCompanyResolutionCoordinatorProvider = Provider<void>((ref) {
  final tracker = _ResolutionTracker();

  ref.listen<bool>(isAuthenticatedProvider, (previous, next) {
    if (previous == true && next == false) {
      tracker.lastResolvedKey = null;
      tracker.generation += 1;
      ref.read(activeCompanyControllerProvider.notifier).clearRuntime();
      return;
    }

    if (previous == false && next == true) {
      tracker.lastResolvedKey = null;
      tracker.generation += 1;
      ref.read(activeCompanyControllerProvider.notifier).markResolving();
    }
  });

  ref.listen<AsyncValue<List<CompanyMembership>>>(userCompaniesProvider, (
    previous,
    next,
  ) {
    if (!ref.read(isAuthenticatedProvider)) {
      return;
    }

    next.when(
      loading: () {
        ref.read(activeCompanyControllerProvider.notifier).markResolving();
      },
      error: (_, _) {
        ref.read(activeCompanyControllerProvider.notifier).markResolving();
      },
      data: (memberships) {
        unawaited(_resolveIfNeeded(ref, tracker, memberships));
      },
    );
  });
});

Future<void> _resolveIfNeeded(
  Ref ref,
  _ResolutionTracker tracker,
  List<CompanyMembership> memberships,
) async {
  if (!ref.read(isAuthenticatedProvider)) {
    return;
  }

  final userId = ref.read(authSessionProvider)?.user.id;
  final key = _resolutionKey(userId, memberships);
  final current = ref.read(activeCompanyControllerProvider);

  if (_shouldSkipResolution(current: current, key: key, tracker: tracker)) {
    return;
  }

  final generation = ++tracker.generation;
  tracker.lastResolvedKey = key;

  if (userId == null) {
    if (generation != tracker.generation) {
      return;
    }
    ref
        .read(activeCompanyControllerProvider.notifier)
        .applyResolution(context: null, resolved: true);
    return;
  }

  final resolution = await ref
      .read(resolveInitialActiveCompanyUseCaseProvider)
      .call(userId: userId, memberships: memberships);

  if (generation != tracker.generation) {
    return;
  }

  switch (resolution) {
    case InitialActiveCompanyResolved(:final context, :final persistSelection):
      if (persistSelection) {
        final membership = _membershipForContext(memberships, context);
        await ref
            .read(activeCompanyControllerProvider.notifier)
            .selectMembership(userId: userId, membership: membership);
        return;
      }
      ref
          .read(activeCompanyControllerProvider.notifier)
          .applyResolution(context: context, resolved: true);
    case InitialActiveCompanyNeedsSelection():
      ref
          .read(activeCompanyControllerProvider.notifier)
          .applyResolution(context: null, resolved: true);
    case InitialActiveCompanyEmpty():
      ref
          .read(activeCompanyControllerProvider.notifier)
          .applyResolution(context: null, resolved: true);
  }
}

bool _shouldSkipResolution({
  required ActiveCompanyState current,
  required String key,
  required _ResolutionTracker tracker,
}) {
  if (!current.resolved) {
    return false;
  }

  if (tracker.lastResolvedKey == key) {
    return true;
  }

  if (current.context != null) {
    return true;
  }

  return false;
}

CompanyMembership _membershipForContext(
  List<CompanyMembership> memberships,
  ActiveCompanyContext context,
) {
  return memberships.firstWhere(
    (membership) => membership.companyId == context.companyId,
  );
}
