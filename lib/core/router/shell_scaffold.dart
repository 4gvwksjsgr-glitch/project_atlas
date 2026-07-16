import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/companies/presentation/controllers/active_company_controller.dart';
import '../../features/companies/presentation/providers/company_providers.dart';
import '../../features/companies/presentation/widgets/active_company_chip.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/constants/app_ui_constants.dart';

/// Layout adattivo con [NavigationBar] (mobile) o [NavigationRail] (desktop).
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= AppUiConstants.shellBreakpoint;
    final activeCompany = ref.watch(activeCompanyProvider);
    final companiesAsync = ref.watch(userCompaniesProvider);
    final canSwitchCompanies = companiesAsync.maybeWhen(
      data: (memberships) => memberships.length > 1,
      orElse: () => false,
    );

    final companyHeader = activeCompany == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              AppUiConstants.spacingLarge,
              AppUiConstants.spacingMedium,
              AppUiConstants.spacingLarge,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActiveCompanyChip(
                activeCompany: activeCompany,
                canSwitch: canSwitchCompanies,
              ),
            ),
          );

    final railDestinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: Text(l10n.navDashboard),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(l10n.navSettings),
      ),
    ];

    final barDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: l10n.navDashboard,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.navSettings,
      ),
    ];

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: railDestinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?companyHeader,
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?companyHeader,
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: barDestinations,
      ),
    );
  }
}
