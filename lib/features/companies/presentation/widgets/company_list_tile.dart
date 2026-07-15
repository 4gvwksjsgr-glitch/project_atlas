import 'package:flutter/material.dart';

import '../../domain/entities/company_membership.dart';

class CompanyListTile extends StatelessWidget {
  const CompanyListTile({
    super.key,
    required this.membership,
    required this.onTap,
    this.selected = false,
  });

  final CompanyMembership membership;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        leading: Icon(
          Icons.business_outlined,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(membership.company.name),
        subtitle: Text('${membership.company.slug} · ${membership.role.label}'),
        trailing: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
