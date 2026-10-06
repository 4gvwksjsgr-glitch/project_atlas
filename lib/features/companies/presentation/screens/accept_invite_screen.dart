import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/router/user_companies_route_state.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../controllers/accept_invite_controller.dart';
import '../controllers/company_onboarding_controller.dart';
import '../providers/company_providers.dart';

class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  /// Set only after a real accept success; gates post-accept navigation.
  var _awaitingPostAcceptResolution = false;
  var _didNavigateAfterAccept = false;

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

  void _handleAcceptControllerState(
    AcceptInviteControllerState? previous,
    AcceptInviteControllerState next,
  ) {
    if (next.actionStatus == CompanyActionStatus.success &&
        previous?.actionStatus != CompanyActionStatus.success) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.acceptInviteSuccess)));
      _tokenController.clear();
      ref.read(acceptInviteControllerProvider.notifier).clearFeedback();

      // Wait for company route state to become terminal before navigating.
      _awaitingPostAcceptResolution = true;
      // Evaluate current state immediately — it may already be terminal.
      _tryNavigateAfterAccept(ref.read(userCompaniesRouteStateProvider));
    }
  }

  void _tryNavigateAfterAccept(UserCompaniesRouteState routeState) {
    if (!_awaitingPostAcceptResolution || _didNavigateAfterAccept || !mounted) {
      return;
    }

    switch (routeState) {
      case UserCompaniesReady():
        _navigateAfterAccept(RoutePaths.dashboard);
      case UserCompaniesNeedsSelection():
        _navigateAfterAccept(RoutePaths.selectCompany);
      case UserCompaniesLoading():
      case UserCompaniesEmpty():
      case UserCompaniesError():
        // Intermediate / fail-closed: stay on AcceptInviteScreen.
        break;
    }
  }

  void _navigateAfterAccept(String location) {
    if (_didNavigateAfterAccept || !mounted) {
      return;
    }
    _didNavigateAfterAccept = true;
    _awaitingPostAcceptResolution = false;
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(acceptInviteControllerProvider);

    ref.listen(acceptInviteControllerProvider, _handleAcceptControllerState);
    ref.listen(userCompaniesRouteStateProvider, (previous, next) {
      if (_awaitingPostAcceptResolution) {
        _tryNavigateAfterAccept(next);
      }
    });

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
