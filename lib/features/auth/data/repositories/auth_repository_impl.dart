import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/sign_up_result.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasource/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remoteDataSource);

  final AuthRemoteDataSource _remoteDataSource;

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _remoteDataSource.signUp(
        email: email,
        password: password,
      );
      return Success(result.toEntity());
    } on Object catch (error) {
      return Error(ErrorMapper.mapException(error));
    }
  }
}
