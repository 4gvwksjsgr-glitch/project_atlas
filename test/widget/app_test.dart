import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/app.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';

void main() {
  testWidgets('App shows login screen on startup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(null),
          isAuthenticatedProvider.overrideWithValue(false),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Inserisci le tue credenziali per continuare'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Accedi'), findsOneWidget);
  });
}
