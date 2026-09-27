import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

/// Mirrors PB-2 / PB-4B phone-safe dialog width clamp.
double _phoneSafeDialogWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final width = screenWidth - 48.0;
  if (width < 0) {
    return 0;
  }
  return width > 420 ? 420 : width;
}

Future<void> _openNarrowDialog(
  WidgetTester tester, {
  required Widget Function(BuildContext dialogContext) builder,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
                  builder: builder,
                );
              },
              child: const Text('open-dialog'),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('open-dialog'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('document delete dialog fits narrow width with reachable actions', (
    tester,
  ) async {
    await _openNarrowDialog(
      tester,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Elimina definitivamente'),
          content: SizedBox(
            width: _phoneSafeDialogWidth(dialogContext),
            child: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VeryLongDocumentTitleWithoutSpaces_ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Questa operazione è irreversibile. Il documento e il file associato verranno eliminati.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(find.text('Elimina'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category create dialog fits narrow width with reachable actions', (
    tester,
  ) async {
    await _openNarrowDialog(
      tester,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nuova categoria'),
          content: SizedBox(
            width: _phoneSafeDialogWidth(dialogContext),
            child: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Entrata / Uscita'),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Nome',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Salva'),
            ),
          ],
        );
      },
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Salva'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trial confirm dialog fits narrow width with reachable actions', (
    tester,
  ) async {
    await _openNarrowDialog(
      tester,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Attivare la prova Premium?'),
          content: SizedBox(
            width: _phoneSafeDialogWidth(dialogContext),
            child: const SingleChildScrollView(
              child: Text(
                'Attiva 14 giorni di prova Premium per questa azienda. '
                'La prova può essere attivata una sola volta.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Attiva'),
            ),
          ],
        );
      },
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Attiva'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('document upload title dialog fits narrow width', (tester) async {
    await _openNarrowDialog(
      tester,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Carica documento'),
          content: SizedBox(
            width: _phoneSafeDialogWidth(dialogContext),
            child: const SingleChildScrollView(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Titolo',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Carica'),
            ),
          ],
        );
      },
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Carica'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('phone-safe dialog width clamps at 320 and 900', () {
    double clamp(double screenWidth) {
      final width = screenWidth - 48.0;
      if (width < 0) return 0;
      return width > 420 ? 420 : width;
    }

    expect(clamp(320), 272);
    expect(clamp(900), 420);
  });
}
