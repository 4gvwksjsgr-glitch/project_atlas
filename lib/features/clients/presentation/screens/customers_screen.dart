import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../providers/customer_providers.dart';
import '../widgets/customer_list_tile.dart';

/// Clears [FloatingActionButton.extended] + [kFloatingActionButtonMargin]
/// so the last list rows remain reachable above the FAB.
const double _customersFabClearance = 96;

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.customersTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppUiConstants.spacingMedium),
            Text(
              l10n.customersNoActiveCompany,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return CustomersListBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
      canManage: activeCompany.role.canManageCustomers,
    );
  }
}

class CustomersListBody extends ConsumerWidget {
  const CustomersListBody({
    super.key,
    required this.companyId,
    required this.canManage,
  });

  final String companyId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final customersAsync = ref.watch(customersProvider(companyId));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.customersTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppUiConstants.spacingSmall),
            Text(
              l10n.customersSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (canManage) ...[
              const SizedBox(height: AppUiConstants.spacingMedium),
              OutlinedButton.icon(
                onPressed: () => context.push(RoutePaths.customersImport),
                icon: const Icon(Icons.upload_file),
                label: Text(l10n.customersImportButton),
              ),
            ],
            const SizedBox(height: AppUiConstants.spacingLarge),
            Expanded(
              child: customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) {
                  final message = error is StateError
                      ? error.message
                      : l10n.customersLoadError;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: AppUiConstants.spacingMedium),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(customersProvider(companyId)),
                          child: Text(l10n.customersRetry),
                        ),
                      ],
                    ),
                  );
                },
                data: (customers) {
                  if (customers.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.customersEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: customers.length + (canManage ? 1 : 0),
                    separatorBuilder: (context, index) {
                      if (canManage && index == customers.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return const Divider(height: 1);
                    },
                    itemBuilder: (context, index) {
                      if (canManage && index == customers.length) {
                        return const SizedBox(
                          key: Key('customers-fab-clearance'),
                          height: _customersFabClearance,
                        );
                      }
                      final customer = customers[index];
                      return CustomerListTile(
                        customer: customer,
                        onTap: () =>
                            context.push(RoutePaths.customerEdit(customer.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.customerNew),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.customersNewButton),
            )
          : null,
    );
  }
}
