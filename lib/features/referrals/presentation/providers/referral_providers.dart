import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/errors/referral_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../companies/presentation/providers/company_providers.dart';
import '../../data/datasource/pending_referral_local_datasource.dart';
import '../../data/datasource/referral_remote_datasource.dart';
import '../../data/repositories/referral_repository_impl.dart';
import '../../domain/entities/referral_overview.dart';
import '../../domain/repositories/referral_repository.dart';

final referralRemoteDataSourceProvider = Provider<ReferralRemoteDataSource>((
  ref,
) {
  return ReferralRemoteDataSource(ref.watch(supabaseClientProvider));
});

final pendingReferralLocalDataSourceProvider =
    Provider<PendingReferralLocalDataSource>((ref) {
      return PendingReferralLocalDataSource(
        ref.watch(sharedPreferencesProvider),
      );
    });

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepositoryImpl(ref.watch(referralRemoteDataSourceProvider));
});

/// Base URL for sharing referral links (override in tests).
final referralAppBaseUrlProvider = Provider<String>((ref) {
  return Env.appUrl;
});

/// Overview keyed per company.
final referralOverviewProvider = FutureProvider.autoDispose
    .family<ReferralOverview, String>((ref, companyId) async {
      final result = await ref
          .read(referralRepositoryProvider)
          .getReferralOverview(companyId: companyId);

      return result.when(
        success: (overview) => overview,
        error: (failure) => throw StateError(failure.message),
      );
    });

/// After login/signup, claim any stashed referral code (idempotent RPC).
///
/// Watch from [App] so the listener stays alive for the session.
final pendingReferralClaimCoordinatorProvider = Provider<void>((ref) {
  var inFlight = false;

  Future<void> tryClaim() async {
    if (inFlight || !ref.read(isAuthenticatedProvider)) {
      return;
    }
    final local = ref.read(pendingReferralLocalDataSourceProvider);
    final code = local.getPendingCode();
    if (code == null) {
      return;
    }

    inFlight = true;
    try {
      final result = await ref
          .read(referralRepositoryProvider)
          .claimReferral(code: code);
      switch (result) {
        case Success():
          await local.clearPendingCode();
        case Error(:final failure):
          if (ReferralErrorMapper.isTerminalClaimFailure(failure)) {
            await local.clearPendingCode();
          }
      }
    } finally {
      inFlight = false;
    }
  }

  ref.listen<bool>(isAuthenticatedProvider, (previous, next) {
    if (next) {
      unawaited(tryClaim());
    }
  });

  if (ref.read(isAuthenticatedProvider)) {
    unawaited(tryClaim());
  }
});
