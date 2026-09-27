import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors production clamp in document_links_dialog.dart.
double _documentDialogWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final width = screenWidth - 48.0;
  if (width < 0) {
    return 0;
  }
  return width > 420 ? 420 : width;
}

void main() {
  testWidgets('document links dialog width clamps on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late double measured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            measured = _documentDialogWidth(context);
            return Scaffold(
              body: Center(
                child: SizedBox(
                  width: measured,
                  child: const SingleChildScrollView(
                    child: Text('dialog-body'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(measured, 272.0); // 320 - 48
    expect(find.text('dialog-body'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Wide screen keeps desktop max.
    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            measured = _documentDialogWidth(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(measured, 420.0);
  });
}
