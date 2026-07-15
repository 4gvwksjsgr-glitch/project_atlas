import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';

void main() {
  group('goRouterAuthRefreshProvider', () {
    test(
      'notifica quando userCompaniesProvider passa da loading a data',
      () async {
        var loadCount = 0;

        final container = ProviderContainer(
          overrides: [
            authStateChangesProvider.overrideWith(
              (ref) => Stream.value(const AuthStateSnapshot(session: null)),
            ),
            authSessionProvider.overrideWithValue(null),
            isAuthenticatedProvider.overrideWithValue(true),
            userCompaniesProvider.overrideWith((ref) async {
              loadCount += 1;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return [];
            }),
          ],
        );
        addTearDown(container.dispose);

        final refresh = container.read(goRouterAuthRefreshProvider);
        var notifyCount = 0;
        refresh.addListener(() => notifyCount += 1);

        container.read(userCompaniesProvider);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await Future<void>.delayed(Duration.zero);

        expect(loadCount, 1);
        expect(notifyCount, greaterThan(0));
      },
    );

    test('notifica quando userCompaniesProvider va in errore', () async {
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(
            (ref) => Stream.value(const AuthStateSnapshot(session: null)),
          ),
          authSessionProvider.overrideWithValue(null),
          isAuthenticatedProvider.overrideWithValue(true),
          userCompaniesProvider.overrideWith(
            (ref) async => throw StateError('Errore simulato'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final refresh = container.read(goRouterAuthRefreshProvider);
      var notifyCount = 0;
      refresh.addListener(() => notifyCount += 1);

      try {
        await container.read(userCompaniesProvider.future);
      } on StateError {
        // Expected.
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });
  });
}
