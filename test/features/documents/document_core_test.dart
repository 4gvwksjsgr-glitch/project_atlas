import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/documents/data/models/company_document_model.dart';
import 'package:project_atlas/features/documents/data/repositories/document_repository_impl.dart';
import 'package:project_atlas/features/documents/domain/services/document_file_validator.dart';
import 'package:project_atlas/features/documents/domain/value_objects/document_file_rules.dart';
import 'package:project_atlas/features/documents/data/datasource/document_remote_datasource.dart';
import 'package:uuid/uuid.dart';

Uint8List _pdfBytes() =>
    Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
Uint8List _jpegBytes() =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
Uint8List _pngBytes() => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
]);
Uint8List _webpBytes() => Uint8List.fromList([
  0x52,
  0x49,
  0x46,
  0x46,
  0x00,
  0x00,
  0x00,
  0x00,
  0x57,
  0x45,
  0x42,
  0x50,
]);

void main() {
  group('DocumentFileValidator', () {
    test('accetta PDF/JPEG/PNG/WebP validi', () {
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.pdf',
          declaredMimeType: 'application/pdf',
          bytes: _pdfBytes(),
        ),
        isA<DocumentFileValidationSuccess>(),
      );
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.jpg',
          declaredMimeType: 'image/jpeg',
          bytes: _jpegBytes(),
        ),
        isA<DocumentFileValidationSuccess>(),
      );
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.png',
          declaredMimeType: 'image/png',
          bytes: _pngBytes(),
        ),
        isA<DocumentFileValidationSuccess>(),
      );
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.webp',
          declaredMimeType: 'image/webp',
          bytes: _webpBytes(),
        ),
        isA<DocumentFileValidationSuccess>(),
      );
    });

    test('rifiuta file vuoto, troppo grande, incoerente', () {
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.pdf',
          declaredMimeType: null,
          bytes: Uint8List(0),
        ),
        isA<DocumentFileValidationFailure>(),
      );
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.pdf',
          declaredMimeType: null,
          bytes: Uint8List(DocumentFileRules.maxSizeBytes + 1),
        ),
        isA<DocumentFileValidationFailure>(),
      );
      expect(
        DocumentFileValidator.validate(
          fileName: 'a.pdf',
          declaredMimeType: 'application/pdf',
          bytes: _jpegBytes(),
        ),
        isA<DocumentFileValidationFailure>(),
      );
    });

    test('titolo precompilato senza estensione', () {
      expect(
        DocumentFileValidator.suggestedTitleFromFileName('Fattura marzo.pdf'),
        'Fattura marzo',
      );
    });
  });

  group('CompanyDocumentModel', () {
    test('fromJson mappa i campi', () {
      final model = CompanyDocumentModel.fromJson({
        'id': 'd1',
        'company_id': 'c1',
        'uploaded_by': 'u1',
        'title': 'Doc',
        'original_file_name': 'doc.pdf',
        'storage_path': 'c1/d1/o1.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 12,
        'is_archived': false,
        'created_at': '2026-07-26T10:00:00Z',
        'updated_at': '2026-07-26T10:00:00Z',
      });
      final entity = model.toEntity();
      expect(entity.title, 'Doc');
      expect(entity.sizeBytes, 12);
      expect(entity.isArchived, isFalse);
    });
  });

  group('DocumentRepositoryImpl upload', () {
    test('path generato allineato al CHECK database', () async {
      String? uploadedPath;
      final companyId = '11111111-1111-1111-1111-111111111111';
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (payload) async {
            return {
              ...payload,
              'uploaded_by': 'u1',
              'is_archived': false,
              'created_at': '2026-07-26T10:00:00Z',
              'updated_at': '2026-07-26T10:00:00Z',
            };
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {
                uploadedPath = path;
              },
        ),
        uuid: const Uuid(),
      );

      await repo.uploadDocument(
        companyId: companyId,
        title: 'Doc',
        originalFileName: 'doc.pdf',
        mimeType: 'application/pdf',
        canonicalExtension: 'pdf',
        bytes: _pdfBytes(),
      );

      final pattern = RegExp(
        '^$companyId/'
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        r'\.(pdf|jpg|png|webp)$',
      );
      expect(uploadedPath, isNotNull);
      expect(pattern.hasMatch(uploadedPath!), isTrue);
      expect(uploadedPath!.contains('jpeg'), isFalse);
    });

    test('upload riuscito', () async {
      String? uploadedPath;
      Map<String, dynamic>? inserted;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (payload) async {
            inserted = payload;
            return {
              ...payload,
              'uploaded_by': 'u1',
              'is_archived': false,
              'created_at': '2026-07-26T10:00:00Z',
              'updated_at': '2026-07-26T10:00:00Z',
            };
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {
                uploadedPath = path;
              },
        ),
        uuid: const Uuid(),
      );

      final result = await repo.uploadDocument(
        companyId: '11111111-1111-1111-1111-111111111111',
        title: 'Doc',
        originalFileName: 'doc.pdf',
        mimeType: 'application/pdf',
        canonicalExtension: 'pdf',
        bytes: _pdfBytes(),
      );

      expect(result.isSuccess, isTrue);
      expect(uploadedPath, isNotNull);
      expect(inserted, isNotNull);
      expect(inserted!['storage_path'], uploadedPath);
    });

    test('metadata fallito esegue cleanup', () async {
      var deleted = false;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            throw Exception('insert failed');
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {},
          deleteExecutor: (_) async {
            deleted = true;
          },
        ),
      );

      final result = await repo.uploadDocument(
        companyId: '11111111-1111-1111-1111-111111111111',
        title: 'Doc',
        originalFileName: 'doc.pdf',
        mimeType: 'application/pdf',
        canonicalExtension: 'pdf',
        bytes: _pdfBytes(),
      );

      expect(result.isError, isTrue);
      expect(deleted, isTrue);
    });

    test('storage fallito non crea metadata', () async {
      var insertCalled = false;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            insertCalled = true;
            return {};
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {
                throw Exception('upload failed');
              },
        ),
      );

      final result = await repo.uploadDocument(
        companyId: '11111111-1111-1111-1111-111111111111',
        title: 'Doc',
        originalFileName: 'doc.pdf',
        mimeType: 'application/pdf',
        canonicalExtension: 'pdf',
        bytes: _pdfBytes(),
      );

      expect(result.isError, isTrue);
      expect(insertCalled, isFalse);
    });

    test('cleanup fallito non perde errore principale', () async {
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            throw Exception('metadata insert failed');
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {},
          deleteExecutor: (_) async {
            throw Exception('cleanup failed');
          },
        ),
      );

      final result = await repo.uploadDocument(
        companyId: '11111111-1111-1111-1111-111111111111',
        title: 'Doc',
        originalFileName: 'doc.pdf',
        mimeType: 'application/pdf',
        canonicalExtension: 'pdf',
        bytes: _pdfBytes(),
      );

      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('expected error'),
        error: (failure) {
          expect(failure.message.toLowerCase(), isNot(contains('cleanup')));
        },
      );
    });

    test('signed URL on-demand', () async {
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          getExecutor: ({required companyId, required documentId}) async {
            return {
              'id': documentId,
              'company_id': companyId,
              'uploaded_by': 'u1',
              'title': 'Doc',
              'original_file_name': 'doc.pdf',
              'storage_path': '$companyId/$documentId/o1.pdf',
              'mime_type': 'application/pdf',
              'size_bytes': 10,
              'is_archived': false,
              'created_at': '2026-07-26T10:00:00Z',
              'updated_at': '2026-07-26T10:00:00Z',
            };
          },
        ),
        DocumentStorageDataSource.test(
          signedUrlExecutor: ({required path, required expiresIn}) async {
            expect(expiresIn, DocumentFileRules.signedUrlTtlSeconds);
            return 'https://signed.example/$path';
          },
        ),
      );

      final result = await repo.createSignedUrl(
        companyId: '11111111-1111-1111-1111-111111111111',
        documentId: '22222222-2222-2222-2222-222222222222',
      );
      expect(result.isSuccess, isTrue);
      result.when(
        success: (url) => expect(url, contains('https://signed.example/')),
        error: (_) => fail('expected success'),
      );
    });

    test('update title e archive', () async {
      Map<String, dynamic>? lastValues;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          updateExecutor:
              ({
                required companyId,
                required documentId,
                required values,
              }) async {
                lastValues = values;
                return {
                  'id': documentId,
                  'company_id': companyId,
                  'uploaded_by': 'u1',
                  'title': values['title'] ?? 'Doc',
                  'original_file_name': 'doc.pdf',
                  'storage_path': '$companyId/$documentId/o1.pdf',
                  'mime_type': 'application/pdf',
                  'size_bytes': 10,
                  'is_archived': values['is_archived'] ?? false,
                  'created_at': '2026-07-26T10:00:00Z',
                  'updated_at': '2026-07-26T11:00:00Z',
                };
              },
        ),
        DocumentStorageDataSource.test(),
      );

      final renamed = await repo.updateTitle(
        companyId: 'c1',
        documentId: 'd1',
        title: 'Nuovo',
      );
      expect(renamed.isSuccess, isTrue);
      expect(lastValues, {'title': 'Nuovo'});

      final archived = await repo.setArchived(
        companyId: 'c1',
        documentId: 'd1',
        isArchived: true,
      );
      expect(archived.isSuccess, isTrue);
      expect(lastValues, {'is_archived': true});
    });
  });
}
