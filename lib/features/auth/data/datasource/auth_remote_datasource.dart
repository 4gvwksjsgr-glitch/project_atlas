import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../models/auth_user_model.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client, {this.authEmailRedirectTo});

  final SupabaseClient _client;

  /// When null, falls back to [Env.appUrl] (Web).
  /// Used for signup confirmation (`emailRedirectTo`) and password reset.
  final String Function()? authEmailRedirectTo;

  Future<SignUpResultModel> signUp({
    required String email,
    required String password,
  }) async {
    final redirectTo = (authEmailRedirectTo ?? () => Env.appUrl)();
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
    );

    return SignUpResultModel.fromAuthResponse(response);
  }

  Future<AuthUserModel> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException('Sign in response did not include a user');
    }

    return AuthUserModel.fromUser(user);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> resetPasswordForEmail({required String email}) async {
    final redirectTo = (authEmailRedirectTo ?? () => Env.appUrl)();
    await _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  Future<void> updatePassword({required String password}) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  AuthUserModel? getCurrentSessionUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }
    return AuthUserModel.fromUser(user);
  }
}
