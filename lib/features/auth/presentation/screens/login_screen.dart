import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    signInStub(ref);
    context.go(RoutePaths.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppUiConstants.maxContentWidth,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.loginTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.loginSubtitle,
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
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => Validators.requiredField(
                      value,
                      message: l10n.passwordRequired,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  FilledButton(
                    onPressed: _submit,
                    child: Text(l10n.loginButton),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.forgotPassword),
                    child: Text(l10n.goToForgotPassword),
                  ),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.signup),
                    child: Text(l10n.goToSignup),
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
