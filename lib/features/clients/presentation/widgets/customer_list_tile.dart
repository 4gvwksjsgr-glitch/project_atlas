import 'package:flutter/material.dart';

import '../../domain/entities/customer.dart';

class CustomerListTile extends StatelessWidget {
  const CustomerListTile({
    super.key,
    required this.customer,
    required this.onTap,
  });

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (customer.email != null && customer.email!.isNotEmpty) customer.email!,
      if (customer.phone != null && customer.phone!.isNotEmpty) customer.phone!,
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        child: Text(
          customer.name.isNotEmpty
              ? customer.name.substring(0, 1).toUpperCase()
              : '?',
        ),
      ),
      title: Text(customer.name),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
