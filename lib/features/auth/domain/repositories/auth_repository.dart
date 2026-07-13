import '../../../../core/utils/result.dart';
import '../entities/auth_user.dart';
import '../entities/sign_up_result.dart';

abstract interface class AuthRepository {
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  });

  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  });

  Future<Result<void>> signOut();

  Future<Result<void>> resetPassword({required String email});

  Future<Result<void>> updatePassword({required String password});

  Future<Result<AuthUser?>> getCurrentSession();
}
