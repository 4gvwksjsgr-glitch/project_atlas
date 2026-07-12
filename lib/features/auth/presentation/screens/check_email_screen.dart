import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';

class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(RoutePaths.login)),
      ),
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
                  Icons.mark_email_read_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
                Text(
                  l10n.checkEmailTitle,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  l10n.checkEmailSubtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (email != null && email!.isNotEmpty) ...[
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  Text(
                    email!,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppUiConstants.spacingLarge),
                FilledButton(
                  onPressed: () => context.go(RoutePaths.login),
                  child: Text(l10n.checkEmailBackToLogin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
