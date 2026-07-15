import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../domain/entities/active_company_context.dart';

class ActiveCompanyChip extends StatelessWidget {
  const ActiveCompanyChip({
    super.key,
    required this.activeCompany,
    required this.canSwitch,
  });

  final ActiveCompanyContext activeCompany;
  final bool canSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ActionChip(
      avatar: const Icon(Icons.business_outlined, size: 18),
      label: Text('${activeCompany.companyName} · ${activeCompany.role.label}'),
      onPressed: canSwitch ? () => context.go(RoutePaths.selectCompany) : null,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}
