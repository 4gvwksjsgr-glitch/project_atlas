import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/files/app_file_picker.dart';

/// True when tabular import must pick a single MIME format before the OS picker.
bool get needsTabularImportFormatChoice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Small Android-only choice before opening the system document picker.
///
/// Returns `null` if dismissed (caller must not open [AppFilePicker]).
Future<TabularImportFileFormat?> showTabularImportFormatChoice(
  BuildContext context,
) {
  return showModalBottomSheet<TabularImportFileFormat>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(TabularImportFileFormat.csv),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Excel (.xlsx)'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(TabularImportFileFormat.xlsx),
            ),
          ],
        ),
      );
    },
  );
}
