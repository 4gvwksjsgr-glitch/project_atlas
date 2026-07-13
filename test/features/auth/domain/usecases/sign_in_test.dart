import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_in.dart';

class _AuthRepositorySpy implements AuthRepository {
  String? lastEmail;
  String? lastPassword;

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    lastPassword = password;
    return const Success(AuthUser(id: 'user-1', email: 'user@example.com'));
  }

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> signOut() => throw UnimplementedError();

  @override
  Future<Result<void>> resetPassword({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({required String password}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

void main() {
  group('SignIn', () {
    test('normalizza email prima del repository', () async {
      final repository = _AuthRepositorySpy();
      final useCase = SignIn(repository);

      await useCase.call(email: '  User@Example.COM  ', password: 'secret');

      expect(repository.lastEmail, 'user@example.com');
      expect(repository.lastPassword, 'secret');
    });
  });
}
