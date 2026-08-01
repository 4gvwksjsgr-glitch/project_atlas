import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/validators.dart';
import '../../domain/entities/active_company_context.dart';
import '../../../subscription/presentation/widgets/company_plan_card.dart';
import '../controllers/active_company_controller.dart';
import '../controllers/company_onboarding_controller.dart';
import '../controllers/company_settings_controller.dart';

class CompanySettingsScreen extends ConsumerWidget {
  const CompanySettingsScreen({super.key});

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
            Text(
              l10n.companySettingsTitle,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: AppUiConstants.spacingMedium),
            Text(
              l10n.companySettingsNoActiveCompany,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return CompanySettingsForm(
      key: ValueKey(activeCompany.companyId),
      activeCompany: activeCompany,
    );
  }
}

class CompanySettingsForm extends ConsumerStatefulWidget {
  const CompanySettingsForm({super.key, required this.activeCompany});

  final ActiveCompanyContext activeCompany;

  @override
  ConsumerState<CompanySettingsForm> createState() =>
      _CompanySettingsFormState();
}

class _CompanySettingsFormState extends ConsumerState<CompanySettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;

  ActiveCompanyContext get _company => widget.activeCompany;

  bool get _canEdit => _company.role.canEditCompanyProfile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _company.companyName);
    _slugController = TextEditingController(text: _company.companySlug);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canEdit) {
      return;
    }

    final controller = ref.read(
      companySettingsControllerProvider(_company.companyId).notifier,
    );
    if (ref
        .read(companySettingsControllerProvider(_company.companyId))
        .isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await controller.save(
      name: _nameController.text,
      slug: _slugController.text,
    );
  }

  void _handleSettingsState(
    CompanySettingsControllerState? previous,
    CompanySettingsControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        previous?.actionStatus != CompanyActionStatus.success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.companySettingsSaveSuccess)));
      ref
          .read(companySettingsControllerProvider(_company.companyId).notifier)
          .clearFeedback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settingsState = ref.watch(
      companySettingsControllerProvider(_company.companyId),
    );
    final isLoading = settingsState.isLoading;

    ref.listen(
      companySettingsControllerProvider(_company.companyId),
      _handleSettingsState,
    );

    return Padding(
      padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.companySettingsTitle,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              Text(
                l10n.companySettingsSubtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingLarge),
              CompanyPlanCard(companyId: _company.companyId),
              const SizedBox(height: AppUiConstants.spacingLarge),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_outlined),
                title: Text(l10n.categoriesTitle),
                subtitle: Text(l10n.categoriesSettingsLinkSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.settingsCategories),
              ),
              const SizedBox(height: AppUiConstants.spacingLarge),
              Text(
                l10n.dashboardActiveRole(_company.role.label),
                style: theme.textTheme.titleMedium,
              ),
              if (!_canEdit) ...[
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  l10n.companySettingsReadOnlyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppUiConstants.spacingLarge),
              TextFormField(
                controller: _nameController,
                enabled: _canEdit && !isLoading,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.companyNameLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => Validators.requiredField(
                  value,
                  message: l10n.companyNameRequired,
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingMedium),
              TextFormField(
                controller: _slugController,
                enabled: _canEdit && !isLoading,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (_canEdit && !isLoading) {
                    _submit();
                  }
                },
                decoration: InputDecoration(
                  labelText: l10n.companySlugLabel,
                  helperText: l10n.companySlugHelper,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => Validators.slug(
                  value,
                  emptyMessage: l10n.companySlugRequired,
                  invalidMessage: l10n.companySlugInvalid,
                ),
              ),
              if (settingsState.errorMessage != null) ...[
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  settingsState.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_canEdit) ...[
                const SizedBox(height: AppUiConstants.spacingLarge),
                FilledButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.companySettingsSaveButton),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
