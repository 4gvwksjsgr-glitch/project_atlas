import 'package:flutter/material.dart';

import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';

class TransactionListTile extends StatelessWidget {
  const TransactionListTile({
    super.key,
    required this.transaction,
    required this.kindLabel,
    required this.onTap,
  });

  final CashTransaction transaction;
  final String kindLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = transaction.kind == TransactionKind.income;
    final amountPrefix = isIncome ? '+' : '−';
    final amountColor = isIncome
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: amountColor.withValues(alpha: 0.12),
        foregroundColor: amountColor,
        child: Icon(isIncome ? Icons.south_west : Icons.north_east),
      ),
      title: Text(transaction.description),
      subtitle: Text(
        '$kindLabel · ${CalendarDate.toIsoDate(transaction.occurredOn)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        '$amountPrefix${transaction.amount.formatEuro()} €',
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
