import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_up.dart';

class _FakeAuthRepository implements AuthRepository {
  String? lastEmail;

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    return Success(
      SignUpResult(
        user: AuthUser(id: 'user-1', email: email),
        status: SignUpStatus.authenticated,
      ),
    );
  }
}

void main() {
  group('SignUp', () {
    test('normalizes email before calling repository', () async {
      final repository = _FakeAuthRepository();
      final useCase = SignUp(repository);

      await useCase.call(
        email: '  User@Example.COM  ',
        password: 'password123',
      );

      expect(repository.lastEmail, 'user@example.com');
    });
  });
}
