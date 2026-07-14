import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/auth/auth_recovery_bootstrap.dart';
import 'package:project_atlas/core/auth/supabase_auth_uri_handler.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseAuthUriHandler', () {
    test('hasAuthCallbackParams rileva code, token ed error', () {
      expect(
        SupabaseAuthUriHandler.hasAuthCallbackParams(
          Uri.parse('http://localhost:9000/?code=abc'),
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.hasAuthCallbackParams(
          Uri.parse('http://localhost:9000/#access_token=token&type=recovery'),
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.hasAuthCallbackParams(
          Uri.parse(
            'http://localhost:9000/?error=access_denied&error_description=expired',
          ),
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.hasAuthCallbackParams(
          Uri.parse('http://localhost:9000/#/login'),
        ),
        isFalse,
      );
    });

    test('mapAuthLinkError restituisce messaggi comprensibili', () {
      expect(
        SupabaseAuthUriHandler.mapAuthLinkError(
          const AuthException(
            'Code verifier could not be found in local storage.',
          ),
        ),
        contains('browser'),
      );
      expect(
        SupabaseAuthUriHandler.mapAuthLinkError(
          const AuthException('Email link is invalid or has expired'),
        ),
        contains('scaduto'),
      );
    });

    test('isPasswordRecoverySession riconosce recovery da evento o type', () {
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          event: AuthChangeEvent.passwordRecovery,
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          launchUri: Uri.parse('http://localhost:9000/?type=recovery'),
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          event: AuthChangeEvent.signedIn,
        ),
        isFalse,
      );
    });

    test('callback signup PKCE con code non è recovery', () {
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          event: AuthChangeEvent.signedIn,
          launchUri: Uri.parse(
            'http://localhost:9000/?code=signup-confirm-code',
          ),
        ),
        isFalse,
      );
      expect(
        SupabaseAuthUriHandler.hasAuthCallbackParams(
          Uri.parse('http://localhost:9000/?code=signup-confirm-code'),
        ),
        isTrue,
      );
    });

    test('callback recovery PKCE attiva recovery solo con evento o type', () {
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          event: AuthChangeEvent.passwordRecovery,
          launchUri: Uri.parse('http://localhost:9000/?code=recovery-code'),
        ),
        isTrue,
      );
      expect(
        SupabaseAuthUriHandler.isPasswordRecoverySession(
          response: AuthSessionUrlResponse(
            session: Session(
              accessToken: 'token',
              tokenType: 'bearer',
              user: User(
                id: 'user-1',
                appMetadata: {},
                userMetadata: {},
                aud: 'authenticated',
                createdAt: DateTime.utc(2026).toIso8601String(),
              ),
            ),
            redirectType: 'recovery',
          ),
        ),
        isTrue,
      );
    });
  });

  group('AuthRecoveryBootstrap', () {
    test(
      'passwordRecoveryActiveProvider legge recovery pendente al bootstrap',
      () {
        AuthRecoveryBootstrap.activateRecovery();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(container.read(isPasswordRecoveryActiveProvider), isTrue);
      },
    );
  });
}
