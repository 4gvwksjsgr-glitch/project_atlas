import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sign_up_result.dart';
import '../providers/auth_providers.dart';

enum AuthActionStatus { idle, loading, success, error }

class AuthControllerState {
  const AuthControllerState({
    this.actionStatus = AuthActionStatus.idle,
    this.signUpResult,
    this.errorMessage,
  });

  final AuthActionStatus actionStatus;
  final SignUpResult? signUpResult;
  final String? errorMessage;

  bool get isLoading => actionStatus == AuthActionStatus.loading;

  AuthControllerState copyWith({
    AuthActionStatus? actionStatus,
    SignUpResult? signUpResult,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return AuthControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      signUpResult: clearResult ? null : signUpResult ?? this.signUpResult,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AuthController extends Notifier<AuthControllerState> {
  @override
  AuthControllerState build() {
    return const AuthControllerState();
  }

  Future<void> signUp({required String email, required String password}) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: AuthActionStatus.loading,
      clearError: true,
      clearResult: true,
    );

    final result = await ref
        .read(signUpUseCaseProvider)
        .call(email: email, password: password);

    result.when(
      success: (value) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.success,
          signUpResult: value,
          clearError: true,
        );
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearResult: true,
        );
      },
    );
  }

  void resetActionState() {
    state = const AuthControllerState();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthControllerState>(AuthController.new);
