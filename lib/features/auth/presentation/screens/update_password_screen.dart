import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../controllers/auth_controller.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() =>
      _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
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
        .updatePassword(password: _passwordController.text);
  }

  void _handleAuthState(
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
        next.successAction == AuthSuccessAction.updatePassword) {
      final l10n = AppLocalizations.of(context);
      ref.read(authControllerProvider.notifier).resetActionState();
      context.go(RoutePaths.login);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.updatePasswordSuccessMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    ref.listen<AuthControllerState>(authControllerProvider, _handleAuthState);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.updatePasswordTitle)),
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
                  Text(
                    l10n.updatePasswordTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.updatePasswordSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
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
                        : Text(l10n.updatePasswordButton),
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
