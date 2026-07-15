import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/user_companies_route_state.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../../shared/helpers/slug_generator.dart';
import '../../../../shared/helpers/validators.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/company_onboarding_controller.dart';
import '../providers/company_providers.dart';

class CompanyOnboardingScreen extends ConsumerStatefulWidget {
  const CompanyOnboardingScreen({super.key});

  @override
  ConsumerState<CompanyOnboardingScreen> createState() =>
      _CompanyOnboardingScreenState();
}

class _CompanyOnboardingScreenState
    extends ConsumerState<CompanyOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  var _slugManuallyEdited = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_slugManuallyEdited) {
      return;
    }

    final generatedSlug = SlugGenerator.fromName(value);
    _slugController.value = TextEditingValue(
      text: generatedSlug,
      selection: TextSelection.collapsed(offset: generatedSlug.length),
    );
  }

  void _onSlugChanged(String _) {
    _slugManuallyEdited = true;
  }

  Future<void> _submit() async {
    if (ref.read(companyOnboardingControllerProvider).isLoading) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(companyOnboardingControllerProvider.notifier)
        .createCompany(name: _nameController.text, slug: _slugController.text);
  }

  Future<void> _signOut() async {
    if (ref.read(authControllerProvider).isLoading) {
      return;
    }

    await ref.read(authControllerProvider.notifier).signOut();
  }

  void _retryCompaniesLoad() {
    ref.invalidate(userCompaniesProvider);
  }

  void _handleCompanyState(
    CompanyOnboardingControllerState? previous,
    CompanyOnboardingControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        next.createdCompany != null &&
        previous?.actionStatus != CompanyActionStatus.success) {
      ref.read(companyOnboardingControllerProvider.notifier).resetActionState();
    }
  }

  void _handleAuthState(
    AuthControllerState? previous,
    AuthControllerState next,
  ) {
    if (next.actionStatus == AuthActionStatus.error &&
        next.errorMessage != null &&
        previous?.errorMessage != next.errorMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final companyState = ref.watch(companyOnboardingControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final companiesRouteState = ref.watch(userCompaniesRouteStateProvider);
    final isLoading = companyState.isLoading || authState.isLoading;

    ref.listen<CompanyOnboardingControllerState>(
      companyOnboardingControllerProvider,
      _handleCompanyState,
    );
    ref.listen<AuthControllerState>(authControllerProvider, _handleAuthState);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppUiConstants.maxContentWidth,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  Text(
                    l10n.onboardingCompanyTitle,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.onboardingCompanySubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (companiesRouteState case UserCompaniesError(
                    :final message,
                  )) ...[
                    const SizedBox(height: AppUiConstants.spacingMedium),
                    Material(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(
                          AppUiConstants.spacingMedium,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: AppUiConstants.spacingSmall),
                            OutlinedButton(
                              onPressed: isLoading ? null : _retryCompaniesLoad,
                              child: Text(l10n.companiesLoadRetryButton),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (companyState.actionStatus == CompanyActionStatus.error &&
                      companyState.errorMessage != null) ...[
                    const SizedBox(height: AppUiConstants.spacingMedium),
                    Material(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(
                          AppUiConstants.spacingMedium,
                        ),
                        child: Text(
                          companyState.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.companyNameLabel,
                    ),
                    enabled: !isLoading,
                    textInputAction: TextInputAction.next,
                    onChanged: _onNameChanged,
                    validator: (value) => Validators.requiredField(
                      value,
                      message: l10n.companyNameRequired,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  TextFormField(
                    controller: _slugController,
                    decoration: InputDecoration(
                      labelText: l10n.companySlugLabel,
                      helperText: l10n.companySlugHelper,
                    ),
                    enabled: !isLoading,
                    onChanged: _onSlugChanged,
                    validator: (value) => Validators.slug(
                      value,
                      emptyMessage: l10n.companySlugRequired,
                      invalidMessage: l10n.companySlugInvalid,
                    ),
                  ),
                  const SizedBox(height: AppUiConstants.spacingLarge),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.createCompanyButton),
                  ),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.logoutButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
