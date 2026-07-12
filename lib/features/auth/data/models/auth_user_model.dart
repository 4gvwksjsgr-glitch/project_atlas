import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/sign_up_result.dart';

class AuthUserModel {
  const AuthUserModel({required this.id, required this.email});

  final String id;
  final String email;

  factory AuthUserModel.fromUser(User user) {
    return AuthUserModel(id: user.id, email: user.email ?? '');
  }

  AuthUser toEntity() {
    return AuthUser(id: id, email: email);
  }
}

class SignUpResultModel {
  const SignUpResultModel({required this.user, required this.status});

  final AuthUserModel user;
  final SignUpStatus status;

  factory SignUpResultModel.fromAuthResponse(AuthResponse response) {
    final user = response.user;
    if (user == null) {
      throw StateError('Sign up response did not include a user');
    }

    return SignUpResultModel(
      user: AuthUserModel.fromUser(user),
      status: response.session == null
          ? SignUpStatus.emailConfirmationRequired
          : SignUpStatus.authenticated,
    );
  }

  SignUpResult toEntity() {
    return SignUpResult(user: user.toEntity(), status: status);
  }
}
