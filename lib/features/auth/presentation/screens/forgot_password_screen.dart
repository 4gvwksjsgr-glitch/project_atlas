import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../controllers/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
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
        .resetPassword(email: _emailController.text);
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
        next.successAction == AuthSuccessAction.resetPassword) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.resetPasswordSuccessMessage)));
      ref.read(authControllerProvider.notifier).resetActionState();
      context.go(RoutePaths.login);
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
      appBar: AppBar(
        leading: BackButton(
          onPressed: isLoading ? null : () => context.go(RoutePaths.login),
        ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.forgotPasswordTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.forgotPasswordSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: l10n.emailLabel),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !isLoading,
                    validator: (value) => Validators.email(
                      value,
                      emptyMessage: l10n.emailRequired,
                      invalidMessage: l10n.emailInvalid,
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
                        : Text(l10n.forgotPasswordButton),
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
