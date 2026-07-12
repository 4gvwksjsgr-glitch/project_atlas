import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_up.dart';
import 'package:project_atlas/features/auth/presentation/controllers/auth_controller.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';

class _CountingAuthRepository implements AuthRepository {
  int callCount = 0;

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Success(
      const SignUpResult(
        user: AuthUser(id: 'user-1', email: 'user@example.com'),
        status: SignUpStatus.authenticated,
      ),
    );
  }
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

      expect(repository.callCount, 1);
    });
  });
}
