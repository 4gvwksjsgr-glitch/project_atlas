import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'app_file_pick_result.dart';
import 'app_file_picker.dart';
import 'picked_file_handle.dart';
import 'selected_app_file.dart';

/// Apre il picker nativo; iniettabile nei test.
typedef OpenPickedFile =
    Future<PickedFileHandle?> Function({
      required List<XTypeGroup> acceptedTypeGroups,
    });

/// Adapter su [file_selector] `openFile` (selezione singola).
class FileSelectorAppFilePicker implements AppFilePicker {
  FileSelectorAppFilePicker({OpenPickedFile? openPickedFile})
    : _openPickedFile = openPickedFile ?? _defaultOpenPickedFile;

  final OpenPickedFile _openPickedFile;

  /// Allineato a `TabularImportSource.maxFileBytes`.
  static const customerImportMaxBytes = 2 * 1024 * 1024;

  /// Stesso limite tabellare dell'import clienti.
  static const transactionImportMaxBytes = customerImportMaxBytes;

  /// Allineato a `DocumentFileRules.maxSizeBytes`.
  static const documentUploadMaxBytes = 6291456;

  static const _androidNullFormatMessage = 'Seleziona prima CSV o Excel.';

  static Future<PickedFileHandle?> _defaultOpenPickedFile({
    required List<XTypeGroup> acceptedTypeGroups,
  }) async {
    final file = await openFile(acceptedTypeGroups: acceptedTypeGroups);
    if (file == null) {
      return null;
    }
    return _XFilePickedFileHandle(file);
  }

  /// Precise CSV/XLSX filters for non-Android platforms.
  static final customerImportTypeGroups = <XTypeGroup>[
    XTypeGroup(
      label: 'CSV o Excel',
      extensions: const <String>['csv', 'xlsx'],
      mimeTypes: const <String>[
        'text/csv',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
      uniformTypeIdentifiers: const <String>[
        'public.comma-separated-values-text',
        'org.openxmlformats.spreadsheetml.sheet',
        'public.data',
      ],
    ),
  ];

  /// Stessi tipi dell'import clienti: entrambi accettano CSV/XLSX.
  static final transactionImportTypeGroups = customerImportTypeGroups;

  /// Android CSV: single MIME family, no extensions (plugin MIME expansion).
  static final androidCsvImportTypeGroups = <XTypeGroup>[
    XTypeGroup(label: 'CSV', mimeTypes: const <String>['text/*']),
  ];

  /// Android XLSX: single exact MIME, no extensions.
  static final androidXlsxImportTypeGroups = <XTypeGroup>[
    XTypeGroup(
      label: 'Excel (.xlsx)',
      mimeTypes: const <String>[
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    ),
  ];

  static final documentUploadTypeGroups = <XTypeGroup>[
    XTypeGroup(
      label: 'Documenti',
      extensions: const <String>['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: const <String>[
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/webp',
      ],
      uniformTypeIdentifiers: const <String>[
        'com.adobe.pdf',
        'public.jpeg',
        'public.png',
        'org.webmproject.webp',
        'public.image',
        'public.data',
      ],
      webWildCards: const <String>['image/*'],
    ),
  ];

  static bool get _useAndroidTabularCompat =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Resolves tabular type groups. Returns `null` when Android format is missing
  /// (fail-closed; do not open the broken multi-MIME picker).
  static List<XTypeGroup>? tabularImportTypeGroupsFor({
    TabularImportFileFormat? format,
  }) {
    if (!_useAndroidTabularCompat) {
      return customerImportTypeGroups;
    }
    return switch (format) {
      TabularImportFileFormat.csv => androidCsvImportTypeGroups,
      TabularImportFileFormat.xlsx => androidXlsxImportTypeGroups,
      null => null,
    };
  }

  @override
  Future<AppFilePickResult> pickCustomerImportFile({
    TabularImportFileFormat? format,
  }) {
    return _pickTabularImport(
      format: format,
      maxBytesBeforeRead: customerImportMaxBytes,
    );
  }

  @override
  Future<AppFilePickResult> pickTransactionImportFile({
    TabularImportFileFormat? format,
  }) {
    return _pickTabularImport(
      format: format,
      maxBytesBeforeRead: transactionImportMaxBytes,
    );
  }

  Future<AppFilePickResult> _pickTabularImport({
    required TabularImportFileFormat? format,
    required int maxBytesBeforeRead,
  }) {
    final groups = tabularImportTypeGroupsFor(format: format);
    if (groups == null) {
      return Future<AppFilePickResult>.value(
        const AppFilePickFailure(_androidNullFormatMessage),
      );
    }
    return _pickSingle(
      acceptedTypeGroups: groups,
      maxBytesBeforeRead: maxBytesBeforeRead,
      tooLargeMessage: 'Il file supera il limite di 2 MB.',
    );
  }

  @override
  Future<AppFilePickResult> pickDocumentUploadFile() {
    return _pickSingle(
      acceptedTypeGroups: documentUploadTypeGroups,
      maxBytesBeforeRead: documentUploadMaxBytes,
      tooLargeMessage: 'Il file supera il limite di 6 MiB.',
    );
  }

  Future<AppFilePickResult> _pickSingle({
    required List<XTypeGroup> acceptedTypeGroups,
    required int maxBytesBeforeRead,
    required String tooLargeMessage,
  }) async {
    late final PickedFileHandle? handle;
    try {
      handle = await _openPickedFile(acceptedTypeGroups: acceptedTypeGroups);
    } catch (_) {
      return const AppFilePickFailure('Impossibile leggere il file.');
    }

    if (handle == null) {
      return const AppFilePickCancelled();
    }

    final name = handle.name.trim();
    if (name.isEmpty) {
      return const AppFilePickFailure('Impossibile leggere il file.');
    }

    late final int reportedLength;
    try {
      reportedLength = await handle.length();
    } catch (_) {
      return const AppFilePickFailure('Impossibile leggere il file.');
    }

    if (reportedLength > maxBytesBeforeRead) {
      return AppFilePickFailure(tooLargeMessage);
    }

    late final Uint8List bytes;
    try {
      bytes = await handle.readAsBytes();
    } catch (_) {
      return const AppFilePickFailure('Il file non è più disponibile.');
    }

    if (bytes.isEmpty) {
      return const AppFilePickFailure('Il file selezionato è vuoto.');
    }

    // Dimensione definitiva = bytes letti; rifiuta se oltre il limite.
    if (bytes.length > maxBytesBeforeRead) {
      return AppFilePickFailure(tooLargeMessage);
    }

    // Corrispondenza ragionevole rispetto alla length dichiarata.
    if (reportedLength > 0 &&
        (bytes.length - reportedLength).abs() > reportedLength) {
      return const AppFilePickFailure('Impossibile leggere il file.');
    }

    final mimeType = handle.mimeType?.trim();
    return AppFilePickSuccess(
      SelectedAppFile(
        name: name,
        extension: extensionOf(name) ?? '',
        mimeType: (mimeType == null || mimeType.isEmpty)
            ? null
            : mimeType.toLowerCase(),
        size: bytes.length,
        bytes: bytes,
      ),
    );
  }

  /// Estensione lowercase senza punto; `null` se assente.
  static String? extensionOf(String fileName) {
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) {
      return null;
    }
    return trimmed.substring(dot + 1).toLowerCase();
  }
}

final class _XFilePickedFileHandle implements PickedFileHandle {
  _XFilePickedFileHandle(this._file);

  final XFile _file;

  @override
  String get name => _file.name;

  @override
  String? get mimeType => _file.mimeType;

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
