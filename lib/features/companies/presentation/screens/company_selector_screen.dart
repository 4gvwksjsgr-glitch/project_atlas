import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../controllers/active_company_controller.dart';
import '../providers/company_providers.dart';
import '../widgets/company_list_tile.dart';

class CompanySelectorScreen extends ConsumerWidget {
  const CompanySelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final companiesAsync = ref.watch(userCompaniesProvider);
    final activeCompany = ref.watch(activeCompanyProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppUiConstants.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.domain_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
                Text(
                  l10n.companySelectorTitle,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppUiConstants.spacingSmall),
                Text(
                  l10n.companySelectorSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
                companiesAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppUiConstants.spacingLarge),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Text(
                    error is StateError ? error.message : l10n.genericError,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  data: (memberships) {
                    if (memberships.isEmpty) {
                      return Text(l10n.companySelectorEmpty);
                    }

                    return Column(
                      children: [
                        for (final membership in memberships)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppUiConstants.spacingSmall,
                            ),
                            child: CompanyListTile(
                              membership: membership,
                              selected:
                                  activeCompany?.companyId ==
                                  membership.companyId,
                              onTap: () => _selectCompany(
                                context,
                                ref,
                                membership.companyId,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectCompany(
    BuildContext context,
    WidgetRef ref,
    String companyId,
  ) async {
    await ref
        .read(activeCompanyControllerProvider.notifier)
        .selectByCompanyId(companyId);

    if (context.mounted) {
      context.go(RoutePaths.dashboard);
    }
  }
}
