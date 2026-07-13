import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/auth_user.dart';
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
      return Error(ErrorMapper.mapException(error, AuthOperation.signUp));
    }
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _remoteDataSource.signIn(
        email: email,
        password: password,
      );
      return Success(user.toEntity());
    } on Object catch (error) {
      return Error(ErrorMapper.mapException(error, AuthOperation.signIn));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _remoteDataSource.signOut();
      return const Success(null);
    } on Object catch (error) {
      return Error(ErrorMapper.mapException(error, AuthOperation.signOut));
    }
  }

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    try {
      await _remoteDataSource.resetPasswordForEmail(email: email);
    } on Object catch (_) {
      // Messaggio neutro: non rivelare se l'email esiste.
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> updatePassword({required String password}) async {
    try {
      await _remoteDataSource.updatePassword(password: password);
      return const Success(null);
    } on Object catch (error) {
      return Error(
        ErrorMapper.mapException(error, AuthOperation.updatePassword),
      );
    }
  }

  @override
  Future<Result<AuthUser?>> getCurrentSession() async {
    try {
      final user = _remoteDataSource.getCurrentSessionUser();
      return Success(user?.toEntity());
    } on Object catch (error) {
      return Error(ErrorMapper.mapException(error, AuthOperation.getSession));
    }
  }
}
