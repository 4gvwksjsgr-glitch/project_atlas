import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/links/atlas_deep_link_config.dart';

/// Signup email-redirect contract (shared with password reset).
/// Datasource passes this value as Supabase `emailRedirectTo` — verified by
/// code review + resolver tests (no SupabaseClient mock dependency).
void main() {
  group('signup email redirect targets', () {
    test('web uses Env.appUrl-equivalent webAppUrl', () {
      expect(
        resolveAuthEmailRedirectTo(
          isWeb: true,
          webAppUrl: 'http://localhost:8080',
        ),
        'http://localhost:8080',
      );
    });

    test('native uses projectatlas://auth/callback', () {
      expect(
        resolveAuthEmailRedirectTo(
          isWeb: false,
          webAppUrl: 'http://localhost:8080',
        ),
        'projectatlas://auth/callback',
      );
      expect(
        resolveAuthEmailRedirectTo(
          isWeb: false,
          webAppUrl: 'http://localhost:8080',
        ),
        AtlasDeepLinkConfig.authCallbackUri,
      );
    });

    test('signup and password-reset resolvers stay aligned', () {
      for (final isWeb in [true, false]) {
        expect(
          resolveAuthEmailRedirectTo(
            isWeb: isWeb,
            webAppUrl: 'http://localhost:8080',
          ),
          resolvePasswordResetRedirectTo(
            isWeb: isWeb,
            webAppUrl: 'http://localhost:8080',
          ),
        );
      }
    });
  });
}
