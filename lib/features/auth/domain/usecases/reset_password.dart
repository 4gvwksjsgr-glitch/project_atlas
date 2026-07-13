import '../../../../core/utils/result.dart';
import '../../../../shared/extensions/string_extensions.dart';
import '../repositories/auth_repository.dart';

class ResetPassword {
  const ResetPassword(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call({required String email}) {
    return _repository.resetPassword(email: email.normalized);
  }
}
