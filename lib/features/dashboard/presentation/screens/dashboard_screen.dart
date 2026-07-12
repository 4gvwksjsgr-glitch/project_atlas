import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dashboardTitle,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  signOutStub(ref);
                  context.go(RoutePaths.login);
                },
                icon: const Icon(Icons.logout),
                label: Text(l10n.logoutButton),
              ),
            ],
          ),
          const SizedBox(height: AppUiConstants.spacingMedium),
          Text(l10n.dashboardWelcome, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            l10n.dashboardPlaceholder,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppUiConstants.spacingLarge),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
              child: Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: AppUiConstants.spacingMedium),
                  Expanded(
                    child: Text(
                      l10n.dashboardPlaceholder,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
