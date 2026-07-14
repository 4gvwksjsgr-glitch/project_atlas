import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/sign_up_result.dart';
import '../providers/auth_providers.dart';

enum AuthActionStatus { idle, loading, success, error }

enum AuthSuccessAction { signUp, signIn, resetPassword, updatePassword }

class AuthControllerState {
  const AuthControllerState({
    this.actionStatus = AuthActionStatus.idle,
    this.successAction,
    this.signUpResult,
    this.authUser,
    this.errorMessage,
  });

  final AuthActionStatus actionStatus;
  final AuthSuccessAction? successAction;
  final SignUpResult? signUpResult;
  final AuthUser? authUser;
  final String? errorMessage;

  bool get isLoading => actionStatus == AuthActionStatus.loading;

  AuthControllerState copyWith({
    AuthActionStatus? actionStatus,
    AuthSuccessAction? successAction,
    SignUpResult? signUpResult,
    AuthUser? authUser,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
    bool clearSuccessAction = false,
  }) {
    return AuthControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      successAction: clearSuccessAction
          ? null
          : successAction ?? this.successAction,
      signUpResult: clearResult ? null : signUpResult ?? this.signUpResult,
      authUser: clearResult ? null : authUser ?? this.authUser,
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
      clearSuccessAction: true,
    );

    final result = await ref
        .read(signUpUseCaseProvider)
        .call(email: email, password: password);

    result.when(
      success: (value) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.success,
          successAction: AuthSuccessAction.signUp,
          signUpResult: value,
          clearError: true,
        );
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearResult: true,
          clearSuccessAction: true,
        );
      },
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: AuthActionStatus.loading,
      clearError: true,
      clearResult: true,
      clearSuccessAction: true,
    );

    final result = await ref
        .read(signInUseCaseProvider)
        .call(email: email, password: password);

    result.when(
      success: (user) {
        ref.read(passwordRecoveryActiveProvider.notifier).clear();
        state = state.copyWith(
          actionStatus: AuthActionStatus.success,
          successAction: AuthSuccessAction.signIn,
          authUser: user,
          clearError: true,
        );
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearResult: true,
          clearSuccessAction: true,
        );
      },
    );
  }

  Future<void> signOut() async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: AuthActionStatus.loading,
      clearError: true,
      clearSuccessAction: true,
    );

    final result = await ref.read(signOutUseCaseProvider).call();

    result.when(
      success: (_) {
        ref.read(passwordRecoveryActiveProvider.notifier).clear();
        state = const AuthControllerState();
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearSuccessAction: true,
        );
      },
    );
  }

  Future<void> resetPassword({required String email}) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: AuthActionStatus.loading,
      clearError: true,
      clearResult: true,
      clearSuccessAction: true,
    );

    final result = await ref
        .read(resetPasswordUseCaseProvider)
        .call(email: email);

    result.when(
      success: (_) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.success,
          successAction: AuthSuccessAction.resetPassword,
          clearError: true,
        );
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearSuccessAction: true,
        );
      },
    );
  }

  Future<void> updatePassword({required String password}) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: AuthActionStatus.loading,
      clearError: true,
      clearResult: true,
      clearSuccessAction: true,
    );

    final updateResult = await ref
        .read(updatePasswordUseCaseProvider)
        .call(password: password);

    await updateResult.when(
      success: (_) async {
        ref.read(passwordRecoveryActiveProvider.notifier).clear();

        final signOutResult = await ref.read(signOutUseCaseProvider).call();

        signOutResult.when(
          success: (_) {
            state = state.copyWith(
              actionStatus: AuthActionStatus.success,
              successAction: AuthSuccessAction.updatePassword,
              clearError: true,
              clearResult: true,
            );
          },
          error: (failure) {
            state = state.copyWith(
              actionStatus: AuthActionStatus.error,
              errorMessage: failure.message,
              clearSuccessAction: true,
            );
          },
        );
      },
      error: (failure) async {
        state = state.copyWith(
          actionStatus: AuthActionStatus.error,
          errorMessage: failure.message,
          clearResult: true,
          clearSuccessAction: true,
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
