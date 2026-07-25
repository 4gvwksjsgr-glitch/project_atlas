import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../../../clients/domain/entities/customer.dart';
import '../../../clients/presentation/providers/customer_providers.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';
import '../../domain/value_objects/money_amount.dart';
import '../controllers/transaction_form_controller.dart';
import '../providers/transaction_providers.dart';
import '../widgets/transaction_category_picker.dart';
import '../../../categories/domain/entities/transaction_category.dart';

class TransactionFormScreen extends ConsumerWidget {
  const TransactionFormScreen({super.key, this.transactionId});

  /// Null o assente = nuovo movimento.
  final String? transactionId;

  bool get isCreate => transactionId == null || transactionId == 'new';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.transactionsTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: Text(l10n.transactionsNoActiveCompany),
        ),
      );
    }

    final canManage = activeCompany.role.canManageTransactions;
    final resolvedTransactionId = isCreate ? 'new' : transactionId!;

    if (!isCreate) {
      final transactionsAsync = ref.watch(
        transactionsProvider(activeCompany.companyId),
      );

      return transactionsAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(title: Text(l10n.transactionEditTitle)),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) {
          final message = error is StateError
              ? error.message
              : l10n.transactionsLoadError;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.transactionEditTitle)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  FilledButton(
                    onPressed: () => ref.invalidate(
                      transactionsProvider(activeCompany.companyId),
                    ),
                    child: Text(l10n.transactionsRetry),
                  ),
                ],
              ),
            ),
          );
        },
        data: (transactions) {
          CashTransaction? transaction;
          for (final entry in transactions) {
            if (entry.id == resolvedTransactionId) {
              transaction = entry;
              break;
            }
          }

          if (transaction == null) {
            return Scaffold(
              appBar: AppBar(title: Text(l10n.transactionEditTitle)),
              body: Center(child: Text(l10n.transactionNotFound)),
            );
          }

          return TransactionFormBody(
            key: ValueKey(
              '${activeCompany.companyId}-$resolvedTransactionId-'
              '${transaction.updatedAt.toIso8601String()}',
            ),
            companyId: activeCompany.companyId,
            transactionId: resolvedTransactionId,
            initial: transaction,
            canEdit: canManage,
          );
        },
      );
    }

    return TransactionFormBody(
      key: ValueKey('${activeCompany.companyId}-new'),
      companyId: activeCompany.companyId,
      transactionId: 'new',
      initial: null,
      canEdit: canManage,
    );
  }
}

class TransactionFormBody extends ConsumerStatefulWidget {
  const TransactionFormBody({
    super.key,
    required this.companyId,
    required this.transactionId,
    required this.initial,
    required this.canEdit,
  });

  final String companyId;
  final String transactionId;
  final CashTransaction? initial;
  final bool canEdit;

  @override
  ConsumerState<TransactionFormBody> createState() =>
      _TransactionFormBodyState();
}

class _TransactionFormBodyState extends ConsumerState<TransactionFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late TransactionKind _kind;
  late DateTime _occurredOn;
  String? _clientId;
  String? _categoryId;
  TransactionCategory? _keptArchivedCategory;

  TransactionFormKey get _formArg =>
      (companyId: widget.companyId, transactionId: widget.transactionId);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? TransactionKind.expense;
    _occurredOn = initial?.occurredOn ?? CalendarDate.todayLocal();
    _clientId = initial?.clientId;
    _categoryId = initial?.categoryId;
    if (initial?.categoryId != null &&
        initial!.categoryName != null &&
        initial.categoryIsActive == false) {
      _keptArchivedCategory = TransactionCategory(
        id: initial.categoryId!,
        companyId: initial.companyId,
        name: initial.categoryName!,
        kind: initial.kind,
        isActive: false,
        createdAt: initial.createdAt,
        updatedAt: initial.updatedAt,
      );
    }
    _amountController = TextEditingController(
      text: initial?.amount.formatEuro() ?? '',
    );
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (!widget.canEdit) {
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredOn,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _occurredOn = CalendarDate.dateOnly(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!widget.canEdit) {
      return;
    }

    final controller = ref.read(
      transactionFormControllerProvider(_formArg).notifier,
    );
    if (ref.read(transactionFormControllerProvider(_formArg)).isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final MoneyAmount amount;
    try {
      amount = MoneyAmount.parse(_amountController.text);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }

    await controller.save(
      clientId: _clientId,
      categoryId: _categoryId,
      kind: _kind,
      amount: amount,
      occurredOn: _occurredOn,
      description: _descriptionController.text,
      notes: _notesController.text,
    );
  }

  void _handleState(
    TransactionFormControllerState? previous,
    TransactionFormControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        previous?.actionStatus != CompanyActionStatus.success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.transactionId == 'new'
                ? l10n.transactionCreateSuccess
                : l10n.transactionUpdateSuccess,
          ),
        ),
      );
      ref
          .read(transactionFormControllerProvider(_formArg).notifier)
          .clearFeedback();
      if (context.mounted) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final formState = ref.watch(transactionFormControllerProvider(_formArg));
    final isLoading = formState.isLoading;
    final isCreate = widget.transactionId == 'new';
    final title = isCreate
        ? l10n.transactionNewTitle
        : l10n.transactionEditTitle;

    ref.listen(transactionFormControllerProvider(_formArg), _handleState);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.canEdit) ...[
                  Text(
                    l10n.transactionReadOnlyMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                ],
                Text(
                  l10n.transactionKindLabel,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppUiConstants.spacingSmall),
                SegmentedButton<TransactionKind>(
                  segments: [
                    ButtonSegment(
                      value: TransactionKind.income,
                      label: Text(l10n.transactionKindIncome),
                      icon: const Icon(Icons.south_west),
                    ),
                    ButtonSegment(
                      value: TransactionKind.expense,
                      label: Text(l10n.transactionKindExpense),
                      icon: const Icon(Icons.north_east),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: widget.canEdit && !isLoading
                      ? (values) {
                          setState(() {
                            _kind = values.first;
                            _categoryId = null;
                          });
                        }
                      : null,
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                TransactionCategoryPicker(
                  companyId: widget.companyId,
                  kind: _kind,
                  selectedCategoryId: _categoryId,
                  keptArchivedCategory: _keptArchivedCategory?.kind == _kind
                      ? _keptArchivedCategory
                      : null,
                  canEdit: widget.canEdit && !isLoading,
                  onSelected: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                TextFormField(
                  controller: _amountController,
                  enabled: widget.canEdit && !isLoading,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.transactionAmountLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final requiredError = Validators.requiredField(
                      value,
                      message: l10n.transactionAmountRequired,
                    );
                    if (requiredError != null) {
                      return requiredError;
                    }
                    try {
                      MoneyAmount.parse(value!);
                      return null;
                    } on FormatException {
                      return l10n.transactionAmountInvalid;
                    }
                  },
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.transactionDateLabel),
                  subtitle: Text(CalendarDate.toIsoDate(_occurredOn)),
                  trailing: widget.canEdit
                      ? IconButton(
                          onPressed: isLoading ? null : _pickDate,
                          icon: const Icon(Icons.calendar_today),
                        )
                      : null,
                  onTap: widget.canEdit && !isLoading ? _pickDate : null,
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                TextFormField(
                  controller: _descriptionController,
                  enabled: widget.canEdit && !isLoading,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.transactionDescriptionLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => Validators.requiredField(
                    value,
                    message: l10n.transactionDescriptionRequired,
                  ),
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                TextFormField(
                  controller: _notesController,
                  enabled: widget.canEdit && !isLoading,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l10n.transactionNotesLabel,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  l10n.transactionClientLabel,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppUiConstants.spacingSmall),
                _ClientPicker(
                  companyId: widget.companyId,
                  canEdit: widget.canEdit && !isLoading,
                  selectedClientId: _clientId,
                  onSelected: (value) => setState(() => _clientId = value),
                ),
                if (formState.errorMessage != null) ...[
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  Text(
                    formState.errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (widget.canEdit) ...[
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  FilledButton(
                    key: const Key('transaction-save-button'),
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.transactionSaveButton),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientPicker extends ConsumerWidget {
  const _ClientPicker({
    required this.companyId,
    required this.canEdit,
    required this.selectedClientId,
    required this.onSelected,
  });

  final String companyId;
  final bool canEdit;
  final String? selectedClientId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final customersAsync = ref.watch(customersProvider(companyId));

    return customersAsync.when(
      loading: () => Text(l10n.transactionClientsLoading),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.transactionClientNone),
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            l10n.transactionClientsLoadError,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      data: (customers) {
        final selectedStillValid =
            selectedClientId == null ||
            customers.any((c) => c.id == selectedClientId);
        final effectiveClientId = selectedStillValid ? selectedClientId : null;
        final selectedLabel = effectiveClientId == null
            ? l10n.transactionClientNone
            : customers.firstWhere((c) => c.id == effectiveClientId).name;

        return InputDecorator(
          decoration: const InputDecoration(border: OutlineInputBorder()),
          child: PopupMenuButton<String?>(
            key: const Key('transaction-client-menu'),
            enabled: canEdit,
            onSelected: onSelected,
            itemBuilder: (context) => [
              PopupMenuItem<String?>(
                value: null,
                child: Text(l10n.transactionClientNone),
              ),
              ...customers.map(
                (Customer customer) => PopupMenuItem<String?>(
                  value: customer.id,
                  child: Text(customer.name),
                ),
              ),
            ],
            child: Row(
              children: [
                Expanded(child: Text(selectedLabel)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }
}
