import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../widgets/dashboard_members_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final activeCompany = ref.watch(activeCompanyProvider);

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
          if (activeCompany == null) ...[
            const SizedBox(height: AppUiConstants.spacingMedium),
            Text(
              l10n.dashboardNoActiveCompany,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: AppUiConstants.spacingSmall),
              child: Text(
                l10n.dashboardCompanyWelcome(activeCompany.companyName),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppUiConstants.spacingSmall),
              child: Text(
                l10n.dashboardCompanySlug(activeCompany.companySlug),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppUiConstants.spacingSmall),
              child: Text(
                l10n.dashboardActiveRole(activeCompany.role.label),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppUiConstants.spacingLarge),
            DashboardMembersCard(companyId: activeCompany.companyId),
          ],
        ],
      ),
    );
  }
}
