import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../controllers/auth_controller.dart';

class CompanyOnboardingPlaceholderScreen extends ConsumerStatefulWidget {
  const CompanyOnboardingPlaceholderScreen({super.key});

  @override
  ConsumerState<CompanyOnboardingPlaceholderScreen> createState() =>
      _CompanyOnboardingPlaceholderScreenState();
}

class _CompanyOnboardingPlaceholderScreenState
    extends ConsumerState<CompanyOnboardingPlaceholderScreen> {
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
  }

  Future<void> _signOut() async {
    if (ref.read(authControllerProvider).isLoading) {
      return;
    }

    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    ref.listen<AuthControllerState>(authControllerProvider, _handleAuthState);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppUiConstants.maxContentWidth,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.business_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
                Text(
                  l10n.onboardingCompanyTitle,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  l10n.onboardingCompanyPlaceholder,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : _signOut,
                  icon: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout),
                  label: Text(l10n.logoutButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
