import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/files/app_file_pick_result.dart';
import 'package:project_atlas/core/files/app_file_picker.dart';
import 'package:project_atlas/core/files/file_selector_app_file_picker.dart';
import 'package:project_atlas/core/files/picked_file_handle.dart';

class _FakeHandle implements PickedFileHandle {
  _FakeHandle({
    required this.name,
    this.mimeType,
    required this.lengthValue,
    this.bytes,
    this.lengthError,
    this.readError,
  });

  @override
  final String name;

  @override
  final String? mimeType;

  final int lengthValue;
  final Uint8List? bytes;
  final Object? lengthError;
  final Object? readError;

  var lengthCalls = 0;
  var readCalls = 0;

  @override
  Future<int> length() async {
    lengthCalls += 1;
    if (lengthError != null) {
      throw lengthError!;
    }
    return lengthValue;
  }

  @override
  Future<Uint8List> readAsBytes() async {
    readCalls += 1;
    if (readError != null) {
      throw readError!;
    }
    return bytes ?? Uint8List(0);
  }
}

void _expectAndroidCsvGroup(XTypeGroup group) {
  expect(group.mimeTypes, equals(const <String>['text/*']));
  expect(group.extensions ?? const <String>[], isEmpty);
  expect(group.mimeTypes, isNot(contains('*/*')));
}

void _expectAndroidXlsxGroup(XTypeGroup group) {
  expect(
    group.mimeTypes,
    equals(const <String>[
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ]),
  );
  expect(group.extensions ?? const <String>[], isEmpty);
  expect(group.mimeTypes, isNot(contains('*/*')));
}

void _expectPreciseTabularGroup(XTypeGroup group) {
  expect(group.extensions, containsAll(<String>['csv', 'xlsx']));
  expect(
    group.mimeTypes,
    containsAll(<String>[
      'text/csv',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ]),
  );
  expect(group.mimeTypes, isNot(contains('*/*')));
}

void main() {
  // flutter_test defaults to Android; keep non-Android for null-format paths.
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('FileSelectorAppFilePicker', () {
    test('annullamento → AppFilePickCancelled', () async {
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => null,
      );

      final result = await picker.pickCustomerImportFile();
      expect(result, isA<AppFilePickCancelled>());
    });

    test('XFile valido → success con bytes e size definitivi', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final handle = _FakeHandle(
        name: 'clienti.csv',
        mimeType: 'text/csv',
        lengthValue: 4,
        bytes: bytes,
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickCustomerImportFile();
      expect(result, isA<AppFilePickSuccess>());
      final file = (result as AppFilePickSuccess).file;
      expect(file.name, 'clienti.csv');
      expect(file.extension, 'csv');
      expect(file.mimeType, 'text/csv');
      expect(file.size, 4);
      expect(file.bytes, bytes);
      expect(handle.lengthCalls, 1);
      expect(handle.readCalls, 1);
    });

    test('errore readAsBytes → file non più disponibile', () async {
      final handle = _FakeHandle(
        name: 'a.csv',
        lengthValue: 10,
        readError: Exception('gone'),
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickCustomerImportFile();
      expect(result, isA<AppFilePickFailure>());
      expect(
        (result as AppFilePickFailure).message,
        'Il file non è più disponibile.',
      );
    });

    test('errore length → impossibile leggere', () async {
      final handle = _FakeHandle(
        name: 'a.csv',
        lengthValue: 0,
        lengthError: Exception('len'),
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickDocumentUploadFile();
      expect(result, isA<AppFilePickFailure>());
      expect(
        (result as AppFilePickFailure).message,
        'Impossibile leggere il file.',
      );
    });

    test(
      'length oltre limite documenti → rifiuto prima di readAsBytes',
      () async {
        final handle = _FakeHandle(
          name: 'big.pdf',
          lengthValue: FileSelectorAppFilePicker.documentUploadMaxBytes + 1,
          bytes: Uint8List(1),
        );
        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async => handle,
        );

        final result = await picker.pickDocumentUploadFile();
        expect(result, isA<AppFilePickFailure>());
        expect(
          (result as AppFilePickFailure).message,
          'Il file supera il limite di 6 MiB.',
        );
        expect(handle.readCalls, 0);
      },
    );

    test('bytes vuoti → messaggio dedicato', () async {
      final handle = _FakeHandle(
        name: 'empty.pdf',
        lengthValue: 0,
        bytes: Uint8List(0),
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickDocumentUploadFile();
      expect(result, isA<AppFilePickFailure>());
      expect(
        (result as AppFilePickFailure).message,
        'Il file selezionato è vuoto.',
      );
    });

    test('mimeType null resta null', () async {
      final handle = _FakeHandle(
        name: 'doc.PDF',
        mimeType: null,
        lengthValue: 3,
        bytes: Uint8List.fromList([0x25, 0x50, 0x44]),
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickDocumentUploadFile();
      final file = (result as AppFilePickSuccess).file;
      expect(file.mimeType, isNull);
      expect(file.extension, 'pdf');
    });

    test('nome con più punti e estensione uppercase', () async {
      final handle = _FakeHandle(
        name: 'report.finale.XLSX',
        mimeType:
            'Application/VND.OpenXMLFormats-Officedocument.Spreadsheetml.Sheet',
        lengthValue: 2,
        bytes: Uint8List.fromList([0x50, 0x4B]),
      );
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async => handle,
      );

      final result = await picker.pickCustomerImportFile();
      final file = (result as AppFilePickSuccess).file;
      expect(file.name, 'report.finale.XLSX');
      expect(file.extension, 'xlsx');
      expect(
        file.mimeType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });

    test('eccezione openFile → impossibile leggere', () async {
      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async {
          throw Exception('picker');
        },
      );

      final result = await picker.pickCustomerImportFile();
      expect(result, isA<AppFilePickFailure>());
      expect(
        (result as AppFilePickFailure).message,
        'Impossibile leggere il file.',
      );
    });

    test('type group documenti espone estensioni e MIME richiesti', () {
      final group = FileSelectorAppFilePicker.documentUploadTypeGroups.single;
      expect(
        group.extensions,
        containsAll(<String>['pdf', 'jpg', 'jpeg', 'png', 'webp']),
      );
      expect(
        group.mimeTypes,
        containsAll(<String>[
          'application/pdf',
          'image/jpeg',
          'image/png',
          'image/webp',
        ]),
      );
    });

    test('type group import espone csv/xlsx', () {
      final group = FileSelectorAppFilePicker.customerImportTypeGroups.single;
      expect(group.extensions, containsAll(<String>['csv', 'xlsx']));
      expect(
        group.mimeTypes,
        containsAll(<String>[
          'text/csv',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]),
      );
    });

    test('Android customer csv uses text/* group without extensions', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      List<XTypeGroup>? captured;

      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async {
          captured = acceptedTypeGroups;
          return null;
        },
      );

      await picker.pickCustomerImportFile(format: TabularImportFileFormat.csv);

      expect(captured, isNotNull);
      expect(captured, hasLength(1));
      _expectAndroidCsvGroup(captured!.single);
    });

    test(
      'Android customer xlsx uses exact XLSX MIME without extensions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickCustomerImportFile(
          format: TabularImportFileFormat.xlsx,
        );

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        _expectAndroidXlsxGroup(captured!.single);
      },
    );

    test(
      'Android transaction csv uses text/* group without extensions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickTransactionImportFile(
          format: TabularImportFileFormat.csv,
        );

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        _expectAndroidCsvGroup(captured!.single);
      },
    );

    test(
      'Android transaction xlsx uses exact XLSX MIME without extensions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickTransactionImportFile(
          format: TabularImportFileFormat.xlsx,
        );

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        _expectAndroidXlsxGroup(captured!.single);
      },
    );

    test('Android null format fails closed without opening picker', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var openCalls = 0;

      final picker = FileSelectorAppFilePicker(
        openPickedFile: ({required acceptedTypeGroups}) async {
          openCalls += 1;
          return null;
        },
      );

      final result = await picker.pickCustomerImportFile();
      expect(result, isA<AppFilePickFailure>());
      expect(
        (result as AppFilePickFailure).message,
        'Seleziona prima CSV o Excel.',
      );
      expect(openCalls, 0);

      final txResult = await picker.pickTransactionImportFile();
      expect(txResult, isA<AppFilePickFailure>());
      expect(openCalls, 0);
    });

    test(
      'non-Android customer import with null format preserves precise group',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickCustomerImportFile();

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        _expectPreciseTabularGroup(captured!.single);
      },
    );

    test(
      'non-Android transaction import with null format preserves precise group',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickTransactionImportFile();

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        _expectPreciseTabularGroup(captured!.single);
      },
    );

    test(
      'Android document upload keeps precise pdf/image group, not */*',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        List<XTypeGroup>? captured;

        final picker = FileSelectorAppFilePicker(
          openPickedFile: ({required acceptedTypeGroups}) async {
            captured = acceptedTypeGroups;
            return null;
          },
        );

        await picker.pickDocumentUploadFile();

        expect(captured, isNotNull);
        expect(captured, hasLength(1));
        final group = captured!.single;
        expect(
          group.extensions,
          containsAll(<String>['pdf', 'jpg', 'jpeg', 'png', 'webp']),
        );
        expect(
          group.mimeTypes,
          containsAll(<String>[
            'application/pdf',
            'image/jpeg',
            'image/png',
            'image/webp',
          ]),
        );
        expect(group.mimeTypes, isNot(contains('*/*')));
      },
    );
  });
}
