import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/di/providers.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/files/app_file_pick_result.dart';
import 'package:project_atlas/core/files/app_file_picker.dart';
import 'package:project_atlas/core/files/file_selector_app_file_picker.dart';
import 'package:project_atlas/core/files/picked_file_handle.dart';
import 'package:project_atlas/core/files/selected_app_file.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/documents/domain/entities/company_document.dart';
import 'package:project_atlas/features/documents/domain/repositories/document_repository.dart';
import 'package:project_atlas/features/documents/domain/services/document_file_validator.dart';
import 'package:project_atlas/features/documents/presentation/providers/document_providers.dart';
import 'package:project_atlas/features/documents/presentation/screens/documents_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _FakePicker implements AppFilePicker {
  _FakePicker(this.result);

  AppFilePickResult result;

  @override
  Future<AppFilePickResult> pickCustomerImportFile() async {
    return const AppFilePickCancelled();
  }

  @override
  Future<AppFilePickResult> pickDocumentUploadFile() async => result;
}

class _RecordingRepo implements DocumentRepository {
  String? lastOriginalFileName;
  String? lastMimeType;
  List<int>? lastBytes;

  @override
  Future<Result<List<CompanyDocument>>> getDocuments({
    required String companyId,
  }) async {
    return const Success([]);
  }

  @override
  Future<Result<CompanyDocument>> uploadDocument({
    required String companyId,
    required String title,
    required String originalFileName,
    required String mimeType,
    required String canonicalExtension,
    required List<int> bytes,
  }) async {
    lastOriginalFileName = originalFileName;
    lastMimeType = mimeType;
    lastBytes = bytes;
    return Success(
      CompanyDocument(
        id: 'd1',
        companyId: companyId,
        uploadedBy: 'u1',
        title: title,
        originalFileName: originalFileName,
        storagePath: '$companyId/d1/o1.pdf',
        mimeType: mimeType,
        sizeBytes: bytes.length,
        isArchived: false,
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
      ),
    );
  }

  @override
  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  }) async {
    return const Success('https://example.test/signed');
  }

  @override
  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  }) async {
    return const Error(NetworkFailure('unused'));
  }

  @override
  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) async {
    return const Error(NetworkFailure('unused'));
  }

  @override
  Future<Result<CompanyDocument>> updateDocumentLinks({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async {
    return const Error(NetworkFailure('unused'));
  }

  @override
  Future<Result<void>> deleteDocumentPermanently({
    required String companyId,
    required String documentId,
  }) async {
    return const Error(NetworkFailure('unused'));
  }
}

ActiveCompanyContext _owner() {
  return const ActiveCompanyContext(
    companyId: 'c1',
    companyName: 'Acme',
    companySlug: 'acme',
    role: CompanyRole.owner,
    membershipId: 'm1',
  );
}

Uint8List _pdfBytes() =>
    Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);

void main() {
  testWidgets('documenti: selezione annullata non mostra snackbar', (
    tester,
  ) async {
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          documentRepositoryProvider.overrideWithValue(repo),
          appFilePickerProvider.overrideWithValue(
            _FakePicker(const AppFilePickCancelled()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: DocumentsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('documents-upload-fab')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.lastBytes, isNull);
  });

  testWidgets('documenti: errore lettura mostra messaggio senza path', (
    tester,
  ) async {
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          documentRepositoryProvider.overrideWithValue(repo),
          appFilePickerProvider.overrideWithValue(
            _FakePicker(
              const AppFilePickFailure('Il file non è più disponibile.'),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: DocumentsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('documents-upload-fab')));
    await tester.pumpAndSettle();

    expect(find.text('Il file non è più disponibile.'), findsOneWidget);
    expect(repo.lastBytes, isNull);
  });

  testWidgets('documenti: PDF valido apre dialog e carica', (tester) async {
    final bytes = _pdfBytes();
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          documentRepositoryProvider.overrideWithValue(repo),
          appFilePickerProvider.overrideWithValue(
            _FakePicker(
              AppFilePickSuccess(
                SelectedAppFile(
                  name: 'Contratto.PDF',
                  extension: 'pdf',
                  mimeType: null,
                  size: bytes.length,
                  bytes: bytes,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: DocumentsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('documents-upload-fab')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('documents-upload-confirm')));
    await tester.pumpAndSettle();

    expect(repo.lastOriginalFileName, 'Contratto.PDF');
    expect(repo.lastMimeType, 'application/pdf');
    expect(repo.lastBytes, bytes);
    expect(find.text('Documento caricato.'), findsOneWidget);
  });

  test('documenti: oversize rifiutato prima di readAsBytes', () async {
    final handle = _LengthOnlyHandle(
      name: 'big.pdf',
      lengthValue: FileSelectorAppFilePicker.documentUploadMaxBytes + 1,
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
  });

  test('documenti: MIME null e validatore firme ancora eseguito', () {
    final result = DocumentFileValidator.validate(
      fileName: 'scan.jpg',
      declaredMimeType: null,
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
    );
    expect(result, isA<DocumentFileValidationSuccess>());
    expect((result as DocumentFileValidationSuccess).mimeType, 'image/jpeg');
  });

  test('documenti: file vuoto rifiutato dal validatore', () {
    final result = DocumentFileValidator.validate(
      fileName: 'a.pdf',
      declaredMimeType: null,
      bytes: Uint8List(0),
    );
    expect(result, isA<DocumentFileValidationFailure>());
    expect(
      (result as DocumentFileValidationFailure).message,
      'Il file selezionato è vuoto.',
    );
  });
}

class _LengthOnlyHandle implements PickedFileHandle {
  _LengthOnlyHandle({required this.name, required this.lengthValue});

  @override
  final String name;

  @override
  String? get mimeType => null;

  final int lengthValue;
  var readCalls = 0;

  @override
  Future<int> length() async => lengthValue;

  @override
  Future<Uint8List> readAsBytes() async {
    readCalls += 1;
    return Uint8List(1);
  }
}
