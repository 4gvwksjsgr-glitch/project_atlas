import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';

void main() {
  group('passwordRecoveryActiveProvider', () {
    test('signedIn azzera recovery attivo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(passwordRecoveryActiveProvider.notifier);
      notifier.activate();
      expect(container.read(isPasswordRecoveryActiveProvider), isTrue);

      notifier.clear();
      expect(container.read(isPasswordRecoveryActiveProvider), isFalse);
    });
  });
}
