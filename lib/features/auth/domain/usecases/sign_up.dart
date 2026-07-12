import '../../../../core/utils/result.dart';
import '../../../../shared/extensions/string_extensions.dart';
import '../entities/sign_up_result.dart';
import '../repositories/auth_repository.dart';

class SignUp {
  const SignUp(this._repository);

  final AuthRepository _repository;

  Future<Result<SignUpResult>> call({
    required String email,
    required String password,
  }) {
    return _repository.signUp(email: email.normalized, password: password);
  }
}
