import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

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

  /// Allineato a `CustomerImportSource.maxFileBytes`.
  static const customerImportMaxBytes = 2 * 1024 * 1024;

  /// Allineato a `DocumentFileRules.maxSizeBytes`.
  static const documentUploadMaxBytes = 6291456;

  static Future<PickedFileHandle?> _defaultOpenPickedFile({
    required List<XTypeGroup> acceptedTypeGroups,
  }) async {
    final file = await openFile(acceptedTypeGroups: acceptedTypeGroups);
    if (file == null) {
      return null;
    }
    return _XFilePickedFileHandle(file);
  }

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

  @override
  Future<AppFilePickResult> pickCustomerImportFile() {
    return _pickSingle(
      acceptedTypeGroups: customerImportTypeGroups,
      maxBytesBeforeRead: customerImportMaxBytes,
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
