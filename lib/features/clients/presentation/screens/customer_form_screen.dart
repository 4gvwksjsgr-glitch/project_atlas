import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/customer.dart';
import '../controllers/customer_form_controller.dart';
import '../providers/customer_providers.dart';

class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.customerId});

  /// Null o assente = nuovo cliente.
  final String? customerId;

  bool get isCreate => customerId == null || customerId == 'new';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.customersTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: Text(l10n.customersNoActiveCompany),
        ),
      );
    }

    final canManage = activeCompany.role.canManageCustomers;
    final resolvedCustomerId = isCreate ? 'new' : customerId!;

    if (!isCreate) {
      final customersAsync = ref.watch(
        customersProvider(activeCompany.companyId),
      );

      return customersAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(title: Text(l10n.customerEditTitle)),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) {
          final message = error is StateError
              ? error.message
              : l10n.customersLoadError;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.customerEditTitle)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  FilledButton(
                    onPressed: () => ref.invalidate(
                      customersProvider(activeCompany.companyId),
                    ),
                    child: Text(l10n.customersRetry),
                  ),
                ],
              ),
            ),
          );
        },
        data: (customers) {
          Customer? customer;
          for (final entry in customers) {
            if (entry.id == resolvedCustomerId) {
              customer = entry;
              break;
            }
          }

          if (customer == null) {
            return Scaffold(
              appBar: AppBar(title: Text(l10n.customerEditTitle)),
              body: Center(child: Text(l10n.customerNotFound)),
            );
          }

          return CustomerFormBody(
            key: ValueKey(
              '${activeCompany.companyId}-$resolvedCustomerId-${customer.updatedAt.toIso8601String()}',
            ),
            companyId: activeCompany.companyId,
            customerId: resolvedCustomerId,
            initial: customer,
            canEdit: canManage,
          );
        },
      );
    }

    return CustomerFormBody(
      key: ValueKey('${activeCompany.companyId}-new'),
      companyId: activeCompany.companyId,
      customerId: 'new',
      initial: null,
      canEdit: canManage,
    );
  }
}

class CustomerFormBody extends ConsumerStatefulWidget {
  const CustomerFormBody({
    super.key,
    required this.companyId,
    required this.customerId,
    required this.initial,
    required this.canEdit,
  });

  final String companyId;
  final String customerId;
  final Customer? initial;
  final bool canEdit;

  @override
  ConsumerState<CustomerFormBody> createState() => _CustomerFormBodyState();
}

class _CustomerFormBodyState extends ConsumerState<CustomerFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;

  CustomerFormKey get _formArg =>
      (companyId: widget.companyId, customerId: widget.customerId);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _emailController = TextEditingController(text: widget.initial?.email ?? '');
    _phoneController = TextEditingController(text: widget.initial?.phone ?? '');
    _notesController = TextEditingController(text: widget.initial?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.canEdit) {
      return;
    }

    final controller = ref.read(
      customerFormControllerProvider(_formArg).notifier,
    );
    if (ref.read(customerFormControllerProvider(_formArg)).isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await controller.save(
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      notes: _notesController.text,
    );
  }

  void _handleState(
    CustomerFormControllerState? previous,
    CustomerFormControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        previous?.actionStatus != CompanyActionStatus.success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.customerId == 'new'
                ? l10n.customerCreateSuccess
                : l10n.customerUpdateSuccess,
          ),
        ),
      );
      ref
          .read(customerFormControllerProvider(_formArg).notifier)
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
    final formState = ref.watch(customerFormControllerProvider(_formArg));
    final isLoading = formState.isLoading;
    final isCreate = widget.customerId == 'new';
    final title = isCreate ? l10n.customerNewTitle : l10n.customerEditTitle;

    ref.listen(customerFormControllerProvider(_formArg), _handleState);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!widget.canEdit) ...[
                Text(
                  l10n.customerReadOnlyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppUiConstants.spacingLarge),
              ],
              TextFormField(
                controller: _nameController,
                enabled: widget.canEdit && !isLoading,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.customerNameLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => Validators.requiredField(
                  value,
                  message: l10n.customerNameRequired,
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingMedium),
              TextFormField(
                controller: _emailController,
                enabled: widget.canEdit && !isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.customerEmailLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return null;
                  }
                  return Validators.email(
                    value,
                    emptyMessage: l10n.emailRequired,
                    invalidMessage: l10n.emailInvalid,
                  );
                },
              ),
              const SizedBox(height: AppUiConstants.spacingMedium),
              TextFormField(
                controller: _phoneController,
                enabled: widget.canEdit && !isLoading,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.customerPhoneLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingMedium),
              TextFormField(
                controller: _notesController,
                enabled: widget.canEdit && !isLoading,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.customerNotesLabel,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
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
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.customerSaveButton),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
