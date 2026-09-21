import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../controllers/accept_invite_controller.dart';
import '../controllers/company_onboarding_controller.dart';

class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await ref
        .read(acceptInviteControllerProvider.notifier)
        .accept(_tokenController.text);
  }

  void _handleState(
    AcceptInviteControllerState? previous,
    AcceptInviteControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        previous?.actionStatus != CompanyActionStatus.success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.acceptInviteSuccess)),
      );
      ref.read(acceptInviteControllerProvider.notifier).clearFeedback();
      _tokenController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(acceptInviteControllerProvider);

    ref.listen(acceptInviteControllerProvider, _handleState);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.acceptInviteTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePaths.dashboard);
            }
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.acceptInviteSubtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingLarge),
              TextFormField(
                controller: _tokenController,
                enabled: !state.isLoading,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!state.isLoading) {
                    _submit();
                  }
                },
                decoration: InputDecoration(
                  labelText: l10n.acceptInviteTokenLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.acceptInviteTokenRequired;
                  }
                  return null;
                },
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppUiConstants.spacingLarge),
              FilledButton(
                onPressed: state.isLoading ? null : _submit,
                child: state.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.acceptInviteSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
