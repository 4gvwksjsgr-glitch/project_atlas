import '../../../../core/utils/result.dart';
import '../repositories/auth_repository.dart';

class SignOut {
  const SignOut(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call() {
    return _repository.signOut();
  }
}
