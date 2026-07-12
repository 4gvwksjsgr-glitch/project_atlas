import 'auth_user.dart';

enum SignUpStatus { authenticated, emailConfirmationRequired }

class SignUpResult {
  const SignUpResult({required this.user, required this.status});

  final AuthUser user;
  final SignUpStatus status;
}
