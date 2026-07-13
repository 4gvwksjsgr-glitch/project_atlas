import '../../../../core/utils/result.dart';
import '../repositories/auth_repository.dart';

class UpdatePassword {
  const UpdatePassword(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call({required String password}) {
    return _repository.updatePassword(password: password);
  }
}
