import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/links/atlas_deep_link_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verifies AuthRemoteDataSource redirect selection without network.
class _RecordingAuthClient {
  String? lastRedirectTo;
}

void main() {
  test('password reset redirect helper web vs native', () {
    expect(
      resolvePasswordResetRedirectTo(
        isWeb: true,
        webAppUrl: 'http://localhost:8080',
      ),
      'http://localhost:8080',
    );
    expect(
      resolvePasswordResetRedirectTo(
        isWeb: false,
        webAppUrl: 'http://localhost:8080',
      ),
      'projectatlas://auth/callback',
    );
  });

  // Keep a compile-time reference so AuthException import stays intentional
  // if future datasource unit tests expand here.
  test('supabase AuthException type remains available', () {
    expect(AuthException('x'), isA<AuthException>());
    expect(_RecordingAuthClient().lastRedirectTo, isNull);
  });
}
