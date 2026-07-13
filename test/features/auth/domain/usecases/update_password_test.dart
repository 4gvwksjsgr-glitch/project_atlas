import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/update_password.dart';

class _UpdatePasswordRepositorySpy implements AuthRepository {
  String? lastPassword;

  @override
  Future<Result<void>> updatePassword({required String password}) async {
    lastPassword = password;
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
  Future<Result<void>> resetPassword({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

void main() {
  group('UpdatePassword', () {
    test('passa la password al repository', () async {
      final repository = _UpdatePasswordRepositorySpy();
      final useCase = UpdatePassword(repository);

      await useCase.call(password: 'newpassword123');

      expect(repository.lastPassword, 'newpassword123');
    });
  });
}
