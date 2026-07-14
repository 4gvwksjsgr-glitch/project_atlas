import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../companies/presentation/providers/company_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final companiesAsync = ref.watch(userCompaniesProvider);

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
                onPressed: authState.isLoading
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout),
                label: Text(l10n.logoutButton),
              ),
            ],
          ),
          const SizedBox(height: AppUiConstants.spacingMedium),
          Text(l10n.dashboardWelcome, style: theme.textTheme.titleLarge),
          companiesAsync.when(
            data: (memberships) {
              if (memberships.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(
                  top: AppUiConstants.spacingSmall,
                ),
                child: Text(
                  l10n.dashboardCompanyWelcome(memberships.first.company.name),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
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
