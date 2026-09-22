import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/referral_providers.dart';

/// Public landing for `/ref/:code` — stashes code, then signup/login.
class ReferralLandingScreen extends ConsumerStatefulWidget {
  const ReferralLandingScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<ReferralLandingScreen> createState() =>
      _ReferralLandingScreenState();
}

class _ReferralLandingScreenState extends ConsumerState<ReferralLandingScreen> {
  var _stashed = false;
  var _claiming = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final code = widget.code.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context).referralCodeInvalid;
      });
      return;
    }

    try {
      await ref
          .read(pendingReferralLocalDataSourceProvider)
          .setPendingCode(code);
      if (!mounted) {
        return;
      }
      setState(() => _stashed = true);

      if (ref.read(isAuthenticatedProvider)) {
        await _claimIfAuthenticated();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = AppLocalizations.of(context).referralStashError;
      });
    }
  }

  Future<void> _claimIfAuthenticated() async {
    if (_claiming) {
      return;
    }
    setState(() {
      _claiming = true;
      _errorMessage = null;
    });

    final code = widget.code.trim();
    final result = await ref
        .read(referralRepositoryProvider)
        .claimReferral(code: code);

    if (!mounted) {
      return;
    }

    switch (result) {
      case Success():
        await ref
            .read(pendingReferralLocalDataSourceProvider)
            .clearPendingCode();
        if (!mounted) {
          return;
        }
        context.go(RoutePaths.onboardingCompany);
      case Error(:final failure):
        setState(() {
          _claiming = false;
          _errorMessage = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.referralLandingTitle)),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.referralLandingSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppUiConstants.spacingLarge),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else if (_stashed)
              Text(
                l10n.referralCodeSaved,
                style: theme.textTheme.bodyLarge,
              )
            else
              Text(
                l10n.referralLoading,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: AppUiConstants.spacingLarge),
            if (!isAuthenticated) ...[
              FilledButton(
                onPressed: () => context.go(RoutePaths.signup),
                child: Text(l10n.referralContinueSignup),
              ),
              const SizedBox(height: AppUiConstants.spacingMedium),
              OutlinedButton(
                onPressed: () => context.go(RoutePaths.login),
                child: Text(l10n.referralContinueLogin),
              ),
            ] else
              FilledButton(
                onPressed: _claiming ? null : _claimIfAuthenticated,
                child: _claiming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.referralContinueAuthenticated),
              ),
          ],
        ),
      ),
    );
  }
}
