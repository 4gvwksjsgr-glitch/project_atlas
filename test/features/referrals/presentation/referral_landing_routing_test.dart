import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/router/auth_redirect_config.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/referrals/data/datasource/pending_referral_local_datasource.dart';
import 'package:project_atlas/features/referrals/presentation/screens/referral_landing_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('referral route guards', () {
    test('/ref/:code resta accessibile senza auth', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.referral('abc123XYZ'),
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesEmpty(),
        ),
        isNull,
      );
      expect(AuthRedirectConfig.isReferralRoute('/ref/abc'), isTrue);
      expect(AuthRedirectConfig.isProtectedRoute('/ref/abc'), isFalse);
    });

    test('utente autenticato non viene espulso da /ref/:code', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.referral('abc123XYZ'),
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
          companiesState: const UserCompaniesReady(),
        ),
        isNull,
      );
    });
  });

  group('ReferralLandingScreen', () {
    testWidgets('salva il codice e offre signup/login', (tester) async {
      final router = GoRouter(
        initialLocation: RoutePaths.referral('InviteCodeABCDEF12'),
        routes: [
          GoRoute(
            path: RoutePaths.referralPath,
            builder: (context, state) {
              final code = state.pathParameters['code'] ?? '';
              return ReferralLandingScreen(code: code);
            },
          ),
          GoRoute(
            path: RoutePaths.signup,
            builder: (context, state) =>
                const Scaffold(body: Text('signup-page')),
          ),
          GoRoute(
            path: RoutePaths.login,
            builder: (context, state) =>
                const Scaffold(body: Text('login-page')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAuthenticatedProvider.overrideWithValue(false),
            sharedPreferencesProvider.overrideWithValue(appSharedPreferences!),
          ],
          child: MaterialApp.router(
            locale: const Locale('it'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invito referral'), findsOneWidget);
      expect(
        find.text('Codice referral salvato. Completa registrazione o accesso.'),
        findsOneWidget,
      );
      expect(
        PendingReferralLocalDataSource(appSharedPreferences!).getPendingCode(),
        'InviteCodeABCDEF12',
      );

      await tester.tap(find.text('Crea account'));
      await tester.pumpAndSettle();
      expect(find.text('signup-page'), findsOneWidget);
    });
  });
}
