import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/sign_up.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final signUpUseCaseProvider = Provider<SignUp>((ref) {
  return SignUp(ref.watch(authRepositoryProvider));
});

final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);

  yield client.auth.currentSession;

  await for (final state in client.auth.onAuthStateChange) {
    yield state.session;
  }
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider);
  return session.maybeWhen(
    data: (value) => value != null,
    orElse: () => ref.watch(supabaseClientProvider).auth.currentSession != null,
  );
});

Future<void> signInStub(WidgetRef ref) {
  // Login reale verrà implementato in uno step successivo.
  return Future.value();
}

Future<void> signOutStub(WidgetRef ref) async {
  await ref.read(supabaseClientProvider).auth.signOut();
}
