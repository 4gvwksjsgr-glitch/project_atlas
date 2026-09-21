import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../providers/subscription_providers.dart';

/// When false, [CheckoutReturnRefreshController] skips [AppLifecycleListener]
/// (tests drive resume via [CheckoutReturnRefreshController.debugHandleLifecycle]).
final checkoutReturnRefreshAttachLifecycleProvider = Provider<bool>((ref) {
  return true;
});

/// Transient post-checkout overview refresh for the company that launched checkout.
///
/// Does not store provider/customer/subscription IDs and never grants Premium locally.
/// Authority remains [companySubscriptionOverviewProvider] / backend overview.
class CheckoutReturnRefreshState {
  const CheckoutReturnRefreshState({
    this.pendingCompanyId,
    this.attemptsCompleted = 0,
    this.isRefreshing = false,
  });

  /// Company that initiated checkout; null when no refresh is pending.
  final String? pendingCompanyId;
  final int attemptsCompleted;
  final bool isRefreshing;

  bool get isPending => pendingCompanyId != null;

  CheckoutReturnRefreshState copyWith({
    String? pendingCompanyId,
    int? attemptsCompleted,
    bool? isRefreshing,
    bool clearPending = false,
  }) {
    return CheckoutReturnRefreshState(
      pendingCompanyId: clearPending
          ? null
          : pendingCompanyId ?? this.pendingCompanyId,
      attemptsCompleted: attemptsCompleted ?? this.attemptsCompleted,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class CheckoutReturnRefreshController
    extends Notifier<CheckoutReturnRefreshState> {
  static const int maxAttempts = 3;
  static const Duration retryInterval = Duration(seconds: 2);

  AppLifecycleListener? _lifecycle;
  Timer? _retryTimer;
  Future<void>? _activeRun;
  int _runGeneration = 0;
  bool _disposed = false;

  @override
  CheckoutReturnRefreshState build() {
    _disposed = false;
    if (ref.watch(checkoutReturnRefreshAttachLifecycleProvider)) {
      _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    }
    ref.listen(activeCompanyProvider, (previous, next) {
      final pending = state.pendingCompanyId;
      if (pending == null) {
        return;
      }
      if (next?.companyId != pending) {
        _cancelStalePending();
      }
    });
    ref.onDispose(_disposeResources);
    return const CheckoutReturnRefreshState();
  }

  /// Record that a Premium checkout was launched for [companyId].
  void markPending(String companyId) {
    _retryTimer?.cancel();
    _retryTimer = null;
    _runGeneration += 1;
    state = CheckoutReturnRefreshState(pendingCompanyId: companyId);
  }

  /// Clear pending work without granting anything locally.
  void clearPending() {
    _cancelStalePending();
  }

  @visibleForTesting
  void debugHandleLifecycle(AppLifecycleState lifecycleState) {
    _onLifecycleState(lifecycleState);
  }

  @visibleForTesting
  bool get debugHasLifecycleListener => _lifecycle != null;

  @visibleForTesting
  bool get debugHasActiveTimer => _retryTimer != null;

  @visibleForTesting
  bool get debugRunInFlight => _activeRun != null;

  void _onLifecycleState(AppLifecycleState lifecycleState) {
    if (_disposed) {
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(_onResume());
    }
  }

  Future<void> _onResume() async {
    if (_disposed || !state.isPending) {
      return;
    }
    if (_activeRun != null) {
      return;
    }
    final run = _runBoundedRefresh();
    _activeRun = run;
    try {
      await run;
    } finally {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    }
  }

  Future<void> _runBoundedRefresh() async {
    final generation = _runGeneration;
    final companyId = state.pendingCompanyId;
    if (companyId == null) {
      return;
    }

    if (_disposed) {
      return;
    }
    state = state.copyWith(isRefreshing: true, attemptsCompleted: 0);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_disposed || generation != _runGeneration) {
        return;
      }
      if (!_isActiveCompany(companyId)) {
        _cancelStalePending();
        return;
      }

      final overview = await _refreshOverview(companyId);
      if (_disposed || generation != _runGeneration) {
        return;
      }
      if (!_isActiveCompany(companyId)) {
        _cancelStalePending();
        return;
      }

      state = state.copyWith(attemptsCompleted: attempt);

      if (overview != null &&
          (overview.isEffectivePremium ||
              overview.providerAccessStatus == ProviderAccessStatus.entitled)) {
        _finishSuccess();
        return;
      }

      if (attempt >= maxAttempts) {
        break;
      }

      final delayed = Completer<void>();
      _retryTimer?.cancel();
      _retryTimer = Timer(retryInterval, delayed.complete);
      await delayed.future;
      _retryTimer = null;
      if (_disposed || generation != _runGeneration) {
        return;
      }
    }

    if (_disposed) {
      return;
    }
    // Exhausted retries while still Free — keep backend-derived state; stop loop.
    state = state.copyWith(clearPending: true, isRefreshing: false);
  }

  Future<CompanySubscriptionOverview?> _refreshOverview(
    String companyId,
  ) async {
    if (_disposed) {
      return null;
    }
    try {
      // Single refresh path: invalidate then await the overview provider once.
      ref.invalidate(companySubscriptionOverviewProvider(companyId));
      return await ref.read(
        companySubscriptionOverviewProvider(companyId).future,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isActiveCompany(String companyId) {
    if (_disposed) {
      return false;
    }
    return ref.read(activeCompanyProvider)?.companyId == companyId;
  }

  void _finishSuccess() {
    if (_disposed) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    state = state.copyWith(clearPending: true, isRefreshing: false);
  }

  void _cancelStalePending() {
    _runGeneration += 1;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed) {
      return;
    }
    state = const CheckoutReturnRefreshState();
  }

  void _disposeResources() {
    _disposed = true;
    _runGeneration += 1;
    _retryTimer?.cancel();
    _retryTimer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _activeRun = null;
  }
}

final checkoutReturnRefreshControllerProvider =
    NotifierProvider<
      CheckoutReturnRefreshController,
      CheckoutReturnRefreshState
    >(CheckoutReturnRefreshController.new);
