import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_recovery_bootstrap.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/router/go_router_auth_refresh.dart';
import '../../../companies/presentation/providers/company_providers.dart';
import '../../data/datasource/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/get_current_session.dart';
import '../../domain/usecases/reset_password.dart';
import '../../domain/usecases/sign_in.dart';
import '../../domain/usecases/sign_out.dart';
import '../../domain/usecases/sign_up.dart';
import '../../domain/usecases/update_password.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final signUpUseCaseProvider = Provider<SignUp>((ref) {
  return SignUp(ref.watch(authRepositoryProvider));
});

final signInUseCaseProvider = Provider<SignIn>((ref) {
  return SignIn(ref.watch(authRepositoryProvider));
});

final signOutUseCaseProvider = Provider<SignOut>((ref) {
  return SignOut(ref.watch(authRepositoryProvider));
});

final resetPasswordUseCaseProvider = Provider<ResetPassword>((ref) {
  return ResetPassword(ref.watch(authRepositoryProvider));
});

final updatePasswordUseCaseProvider = Provider<UpdatePassword>((ref) {
  return UpdatePassword(ref.watch(authRepositoryProvider));
});

final getCurrentSessionUseCaseProvider = Provider<GetCurrentSession>((ref) {
  return GetCurrentSession(ref.watch(authRepositoryProvider));
});

/// Snapshot dello stream auth Supabase.
class AuthStateSnapshot {
  const AuthStateSnapshot({
    required this.session,
    this.event,
    this.streamError,
  });

  final Session? session;
  final AuthChangeEvent? event;
  final Object? streamError;
}

class PasswordRecoveryActiveNotifier extends Notifier<bool> {
  @override
  bool build() {
    return AuthRecoveryBootstrap.consumePendingRecovery();
  }

  void activate() => state = true;

  void clear() => state = false;
}

final passwordRecoveryActiveProvider =
    NotifierProvider<PasswordRecoveryActiveNotifier, bool>(
      PasswordRecoveryActiveNotifier.new,
    );

final isPasswordRecoveryActiveProvider = Provider<bool>((ref) {
  return ref.watch(passwordRecoveryActiveProvider);
});

final authStateChangesProvider = StreamProvider<AuthStateSnapshot>((ref) {
  final client = ref.read(supabaseClientProvider);
  final recoveryNotifier = ref.read(passwordRecoveryActiveProvider.notifier);
  final logger = ref.read(appLoggerProvider);
  final controller = StreamController<AuthStateSnapshot>();

  controller.add(AuthStateSnapshot(session: client.auth.currentSession));

  final subscription = client.auth.onAuthStateChange.listen(
    (data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        recoveryNotifier.activate();
      } else if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut) {
        recoveryNotifier.clear();
      }

      controller.add(
        AuthStateSnapshot(session: data.session, event: data.event),
      );
    },
    onError: (Object error, StackTrace stackTrace) {
      logger.error(
        'Errore nello stream auth',
        error: error,
        stackTrace: stackTrace,
      );
      controller.add(
        AuthStateSnapshot(
          session: client.auth.currentSession,
          streamError: error,
        ),
      );
    },
  );

  ref.onDispose(() async {
    await subscription.cancel();
    await controller.close();
  });

  return controller.stream;
});

final authSessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.maybeWhen(
    data: (snapshot) => snapshot.session,
    orElse: () => ref.watch(supabaseClientProvider).auth.currentSession,
  );
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authSessionProvider) != null;
});

final goRouterAuthRefreshProvider = Provider<GoRouterAuthRefresh>((ref) {
  final refresh = GoRouterAuthRefresh();

  ref.listen(authStateChangesProvider, (previous, next) {
    refresh.notifyAuthChanged();
  });
  ref.listen(isPasswordRecoveryActiveProvider, (previous, next) {
    refresh.notifyAuthChanged();
  });
  ref.listen(userCompaniesProvider, (previous, next) {
    refresh.notifyAuthChanged();
  });

  ref.onDispose(refresh.dispose);

  return refresh;
});
