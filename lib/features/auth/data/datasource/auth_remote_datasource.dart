import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/auth_user_model.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<SignUpResultModel> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    return SignUpResultModel.fromAuthResponse(response);
  }
}
