import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/document_error_mapper.dart';
import 'package:project_atlas/core/errors/exceptions.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/features/documents/data/datasource/document_remote_datasource.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('DocumentStorageDataSource.deleteObject', () {
    test('remove non vuoto → deleted', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => ['c1/d1/o1.pdf'],
      );
      expect(
        await ds.deleteObject('c1/d1/o1.pdf'),
        DocumentStorageDeleteResult.deleted,
      );
    });

    test('remove vuoto + file assente → alreadyAbsent', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => const [],
        existsExecutor: (_) async => false,
      );
      expect(
        await ds.deleteObject('c1/d1/o1.pdf'),
        DocumentStorageDeleteResult.alreadyAbsent,
      );
    });

    test('remove vuoto + file presente → no-op exception', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => const [],
        existsExecutor: (_) async => true,
      );
      await expectLater(
        ds.deleteObject('c1/d1/o1.pdf'),
        throwsA(isA<DocumentStorageDeleteNoOpException>()),
      );
    });

    test('probe esistenza errore rete → errore', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => const [],
        existsExecutor: (_) async {
          throw const StorageException('network timeout', statusCode: '0');
        },
      );
      await expectLater(
        ds.deleteObject('c1/d1/o1.pdf'),
        throwsA(isA<StorageException>()),
      );
    });

    test('employee/no-op non è successo', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => const [],
        existsExecutor: (_) async => true,
      );
      await expectLater(
        ds.deleteObject('c1/d1/o1.pdf'),
        throwsA(isA<DocumentStorageDeleteNoOpException>()),
      );
    });

    test('altro tenant/no-op non è successo', () async {
      final ds = DocumentStorageDataSource.test(
        removeExecutor: (_) async => const [],
        existsExecutor: (_) async => true,
      );
      await expectLater(
        ds.deleteObject('other/d1/o1.pdf'),
        throwsA(isA<DocumentStorageDeleteNoOpException>()),
      );
    });
  });

  group('DocumentRemoteDataSource.deleteDocumentMetadata', () {
    test('delete 1 riga → deleted', () async {
      final ds = DocumentRemoteDataSource.test(
        deleteRowsExecutor: ({required companyId, required documentId}) async {
          return [
            {'id': documentId},
          ];
        },
      );
      expect(
        await ds.deleteDocumentMetadata(companyId: 'c1', documentId: 'd1'),
        DocumentMetadataDeleteResult.deleted,
      );
    });

    test('delete 0 righe + get assente → alreadyAbsent', () async {
      final ds = DocumentRemoteDataSource.test(
        deleteRowsExecutor: ({required companyId, required documentId}) async {
          return const [];
        },
        getExecutor: ({required companyId, required documentId}) async {
          throw const PostgrestException(
            message: 'JSON object requested, multiple (or no) rows returned',
            code: 'PGRST116',
          );
        },
      );
      expect(
        await ds.deleteDocumentMetadata(companyId: 'c1', documentId: 'd1'),
        DocumentMetadataDeleteResult.alreadyAbsent,
      );
    });

    test('delete 0 righe + get presente → no-op', () async {
      final ds = DocumentRemoteDataSource.test(
        deleteRowsExecutor: ({required companyId, required documentId}) async {
          return const [];
        },
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
      );
      await expectLater(
        ds.deleteDocumentMetadata(companyId: 'c1', documentId: 'd1'),
        throwsA(isA<DocumentMetadataDeleteNoOpException>()),
      );
    });

    test('delete 0 righe + get errore → errore reale', () async {
      final ds = DocumentRemoteDataSource.test(
        deleteRowsExecutor: ({required companyId, required documentId}) async {
          return const [];
        },
        getExecutor: ({required companyId, required documentId}) async {
          throw const PostgrestException(
            message: 'connection reset',
            code: '57014',
          );
        },
      );
      await expectLater(
        ds.deleteDocumentMetadata(companyId: 'c1', documentId: 'd1'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('error mapping delete', () {
    test('storage no-op → messaggio file', () {
      final failure = DocumentErrorMapper.mapException(
        const DocumentStorageDeleteNoOpException(),
        DocumentOperation.deleteDocumentStorage,
      );
      expect(failure, isA<DocumentStorageDeleteNoOpFailure>());
      expect(failure.message, 'Non è stato possibile eliminare il file.');
    });

    test('metadata no-op → permesso', () {
      final failure = DocumentErrorMapper.mapException(
        const DocumentMetadataDeleteNoOpException(),
        DocumentOperation.deleteDocumentMetadata,
      );
      expect(failure, isA<DocumentMetadataDeleteNoOpFailure>());
      expect(
        failure.message,
        'Non hai i permessi per eliminare questo documento.',
      );
    });

    test('incomplete → messaggio dati', () {
      const failure = IncompleteDocumentDeletionFailure();
      expect(
        failure.message,
        contains('dati del documento non sono stati eliminati'),
      );
    });
  });
}
