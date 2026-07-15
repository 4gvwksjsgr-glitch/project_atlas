import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/constants/app_ui_constants.dart';
import '../../features/companies/presentation/controllers/active_company_controller.dart';
import '../../features/companies/presentation/providers/company_providers.dart';
import '../../features/companies/presentation/widgets/active_company_chip.dart';

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

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Dashboard'),
                ),
              ],
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
        ],
      ),
    );
  }
}
