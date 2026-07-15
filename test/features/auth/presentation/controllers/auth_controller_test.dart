import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_in.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_out.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_up.dart';
import 'package:project_atlas/features/auth/domain/usecases/update_password.dart';
import 'package:project_atlas/features/auth/presentation/controllers/auth_controller.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_state.dart';

class _CountingAuthRepository implements AuthRepository {
  int signUpCallCount = 0;
  int signInCallCount = 0;
  int updatePasswordCallCount = 0;

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) async {
    signUpCallCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Success(
      const SignUpResult(
        user: AuthUser(id: 'user-1', email: 'user@example.com'),
        status: SignUpStatus.authenticated,
      ),
    );
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    signInCallCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const Success(AuthUser(id: 'user-1', email: 'user@example.com'));
  }

  @override
  Future<Result<void>> signOut() async => const Success(null);

  @override
  Future<Result<void>> resetPassword({required String email}) async =>
      const Success(null);

  @override
  Future<Result<void>> updatePassword({required String password}) async {
    updatePasswordCallCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return const Success(null);
  }

  @override
  Future<Result<AuthUser?>> getCurrentSession() async => const Success(null);
}

class _TestActiveCompanyController extends ActiveCompanyController {
  @override
  ActiveCompanyState build() => const ActiveCompanyState(resolved: true);

  @override
  void clearRuntime() {}
}

void main() {
  group('AuthController', () {
    test('ignores duplicate signUp calls while loading', () async {
      final repository = _CountingAuthRepository();
      final container = ProviderContainer(
        overrides: [
          signUpUseCaseProvider.overrideWithValue(SignUp(repository)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);

      final firstCall = controller.signUp(
        email: 'user@example.com',
        password: 'password123',
      );
      final secondCall = controller.signUp(
        email: 'user@example.com',
        password: 'password123',
      );

      await Future.wait([firstCall, secondCall]);

      expect(repository.signUpCallCount, 1);
    });

    test('ignores duplicate signIn calls while loading', () async {
      final repository = _CountingAuthRepository();
      final container = ProviderContainer(
        overrides: [
          signInUseCaseProvider.overrideWithValue(SignIn(repository)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);

      final firstCall = controller.signIn(
        email: 'user@example.com',
        password: 'password123',
      );
      final secondCall = controller.signIn(
        email: 'user@example.com',
        password: 'password123',
      );

      await Future.wait([firstCall, secondCall]);

      expect(repository.signInCallCount, 1);
    });

    test('signIn azzera recovery stale dopo redirect errato', () async {
      final repository = _CountingAuthRepository();
      final container = ProviderContainer(
        overrides: [
          signInUseCaseProvider.overrideWithValue(SignIn(repository)),
        ],
      );
      addTearDown(container.dispose);

      container.read(passwordRecoveryActiveProvider.notifier).activate();
      expect(container.read(isPasswordRecoveryActiveProvider), isTrue);

      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'user@example.com', password: 'password123');

      expect(container.read(isPasswordRecoveryActiveProvider), isFalse);
    });

    test('ignores duplicate updatePassword calls while loading', () async {
      final repository = _CountingAuthRepository();
      final container = ProviderContainer(
        overrides: [
          updatePasswordUseCaseProvider.overrideWithValue(
            UpdatePassword(repository),
          ),
          signOutUseCaseProvider.overrideWithValue(SignOut(repository)),
          activeCompanyControllerProvider.overrideWith(
            _TestActiveCompanyController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);

      final firstCall = controller.updatePassword(password: 'newpassword123');
      final secondCall = controller.updatePassword(password: 'newpassword123');

      await Future.wait([firstCall, secondCall]);

      expect(repository.updatePasswordCallCount, 1);
    });
  });
}
