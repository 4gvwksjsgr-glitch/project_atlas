import '../../../../core/utils/result.dart';
import '../entities/sign_up_result.dart';

abstract interface class AuthRepository {
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  });
}
