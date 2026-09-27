import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

/// Mirrors the phone-safe width clamp used by company_team_screen dialogs.
double _teamDialogWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final width = screenWidth - 48.0;
  if (width < 0) {
    return 0;
  }
  return width > 420 ? 420 : width;
}

void main() {
  testWidgets('team invite token dialog fits narrow portrait width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longToken =
        'tok_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('it'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Invito creato'),
                        content: SizedBox(
                          width: _teamDialogWidth(dialogContext),
                          child: const SingleChildScrollView(
                            child: SelectableText(longToken),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                            child: const Text('Chiudi'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('open-token'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open-token'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('tok_'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
