import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/links/atlas_deep_link_config.dart';

void main() {
  group('AtlasDeepLinkParser', () {
    test('auth callback valid', () {
      final link = AtlasDeepLinkParser.parse(
        Uri.parse('projectatlas://auth/callback'),
      );
      expect(link, isA<AtlasDeepLinkAuthCallback>());
    });

    test('auth callback with query still auth', () {
      final link = AtlasDeepLinkParser.parse(
        Uri.parse('projectatlas://auth/callback?code=abc'),
      );
      expect(link, isA<AtlasDeepLinkAuthCallback>());
    });

    test('referral valid', () {
      final link = AtlasDeepLinkParser.parse(
        Uri.parse('projectatlas://ref/OwnerCodeABCDEF1234'),
      );
      expect(link, isA<AtlasDeepLinkReferral>());
      expect((link as AtlasDeepLinkReferral).code, 'OwnerCodeABCDEF1234');
    });

    test('billing return valid', () {
      final link = AtlasDeepLinkParser.parse(
        Uri.parse('projectatlas://billing/return'),
      );
      expect(link, isA<AtlasDeepLinkBillingReturn>());
    });

    test('foreign scheme rejected', () {
      expect(
        AtlasDeepLinkParser.parse(Uri.parse('https://app.test/ref/ABC')),
        isA<AtlasDeepLinkUnsupported>(),
      );
    });

    test('empty referral rejected', () {
      expect(
        AtlasDeepLinkParser.parse(Uri.parse('projectatlas://ref/')),
        isA<AtlasDeepLinkUnsupported>(),
      );
      expect(
        AtlasDeepLinkParser.parse(Uri.parse('projectatlas://ref')),
        isA<AtlasDeepLinkUnsupported>(),
      );
    });

    test('unexpected auth path rejected', () {
      expect(
        AtlasDeepLinkParser.parse(Uri.parse('projectatlas://auth/other')),
        isA<AtlasDeepLinkUnsupported>(),
      );
    });

    test('malformed string rejected', () {
      expect(
        AtlasDeepLinkParser.parseString(':::not-a-uri'),
        isA<AtlasDeepLinkUnsupported>(),
      );
      expect(
        AtlasDeepLinkParser.parseString(null),
        isA<AtlasDeepLinkUnsupported>(),
      );
    });
  });

  group('resolvePasswordResetRedirectTo', () {
    test('web uses app URL', () {
      expect(
        resolvePasswordResetRedirectTo(
          isWeb: true,
          webAppUrl: 'https://app.example',
        ),
        'https://app.example',
      );
    });

    test('native uses projectatlas auth callback', () {
      expect(
        resolvePasswordResetRedirectTo(
          isWeb: false,
          webAppUrl: 'https://app.example',
        ),
        AtlasDeepLinkConfig.authCallbackUri,
      );
    });
  });
}
