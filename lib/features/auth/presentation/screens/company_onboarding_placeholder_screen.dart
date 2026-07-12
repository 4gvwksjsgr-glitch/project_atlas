import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';

class CompanyOnboardingPlaceholderScreen extends StatelessWidget {
  const CompanyOnboardingPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
