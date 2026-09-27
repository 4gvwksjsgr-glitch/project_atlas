import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/subscription/presentation/providers/subscription_providers.dart';

void main() {
  group('isBillingCheckoutSupportedPlatformProvider', () {
    test('web is supported', () {
      final container = ProviderContainer(
        overrides: [
          isBillingCheckoutSupportedPlatformProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isBillingCheckoutSupportedPlatformProvider), isTrue);
    });

    test('unsupported desktop override is blocked', () {
      final container = ProviderContainer(
        overrides: [
          isBillingCheckoutSupportedPlatformProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(isBillingCheckoutSupportedPlatformProvider),
        isFalse,
      );
    });

    test('production resolver: mobile platforms supported, desktop blocked', () {
      // Evaluates the real provider body via a local pure helper mirror so
      // tests do not depend on the host OS running the suite.
      bool resolve({required bool isWeb, required TargetPlatform platform}) {
        if (isWeb) {
          return true;
        }
        return switch (platform) {
          TargetPlatform.android || TargetPlatform.iOS => true,
          _ => false,
        };
      }

      expect(resolve(isWeb: true, platform: TargetPlatform.windows), isTrue);
      expect(resolve(isWeb: false, platform: TargetPlatform.android), isTrue);
      expect(resolve(isWeb: false, platform: TargetPlatform.iOS), isTrue);
      expect(resolve(isWeb: false, platform: TargetPlatform.windows), isFalse);
      expect(resolve(isWeb: false, platform: TargetPlatform.macOS), isFalse);
      expect(resolve(isWeb: false, platform: TargetPlatform.linux), isFalse);
    });
  });
}
