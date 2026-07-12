import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/extensions/string_extensions.dart';
import '../../../../shared/helpers/validators.dart';
import '../../domain/entities/sign_up_result.dart';
import '../controllers/auth_controller.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  void _handleSignUpState(
    AuthControllerState? previous,
    AuthControllerState next,
  ) {
    if (next.actionStatus == AuthActionStatus.error &&
        next.errorMessage != null &&
        previous?.errorMessage != next.errorMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
    }

    if (next.actionStatus == AuthActionStatus.success &&
        next.signUpResult != null) {
      final result = next.signUpResult!;

      switch (result.status) {
        case SignUpStatus.emailConfirmationRequired:
          context.go(
            RoutePaths.checkEmail,
            extra: _emailController.text.normalized,
          );
        case SignUpStatus.authenticated:
          context.go(RoutePaths.onboardingCompany);
      }

      ref.read(authControllerProvider.notifier).resetActionState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    ref.listen<AuthControllerState>(authControllerProvider, _handleSignUpState);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(RoutePaths.login)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppUiConstants.maxContentWidth,
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.signupTitle, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.signupSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: l10n.emailLabel),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !isLoading,
                    validator: (value) => Validators.email(
                      value,
                      emptyMessage: l10n.emailRequired,
                      invalidMessage: l10n.emailInvalid,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(labelText: l10n.passwordLabel),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    enabled: !isLoading,
                    onChanged: (_) => _formKey.currentState?.validate(),
                    validator: (value) => Validators.minLength(
                      value,
                      minLength: 8,
                      emptyMessage: l10n.passwordRequired,
                      tooShortMessage: l10n.passwordTooShort,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: l10n.confirmPasswordLabel,
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    enabled: !isLoading,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => Validators.confirmPassword(
                      value,
                      originalPassword: _passwordController.text,
                      emptyMessage: l10n.confirmPasswordRequired,
                      mismatchMessage: l10n.confirmPasswordMismatch,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.signupButton),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => context.go(RoutePaths.login),
                    child: Text(l10n.goToLogin),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
