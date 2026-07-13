import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/reset_password.dart';

class _ResetPasswordRepositorySpy implements AuthRepository {
  String? lastEmail;

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    lastEmail = email;
    return const Success(null);
  }

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> signOut() => throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({required String password}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

void main() {
  group('ResetPassword', () {
    test('normalizza email prima del repository', () async {
      final repository = _ResetPasswordRepositorySpy();
      final useCase = ResetPassword(repository);

      await useCase.call(email: '  User@Example.COM  ');

      expect(repository.lastEmail, 'user@example.com');
    });
  });
}
