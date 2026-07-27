import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/documents/domain/entities/company_document.dart';
import 'package:project_atlas/features/documents/domain/repositories/document_repository.dart';
import 'package:project_atlas/features/documents/domain/usecases/document_usecases.dart';

class _Repo implements DocumentRepository {
  Result<CompanyDocument>? linksResult;
  Result<void>? deleteResult;
  String? lastClientId;
  String? lastTransactionId;
  var deleteCalls = 0;

  @override
  Future<Result<List<CompanyDocument>>> getDocuments({
    required String companyId,
  }) async => const Success([]);

  @override
  Future<Result<CompanyDocument>> uploadDocument({
    required String companyId,
    required String title,
    required String originalFileName,
    required String mimeType,
    required String canonicalExtension,
    required List<int> bytes,
  }) async => throw UnimplementedError();

  @override
  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  }) async => throw UnimplementedError();

  @override
  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) async => throw UnimplementedError();

  @override
  Future<Result<CompanyDocument>> updateDocumentLinks({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async {
    lastClientId = clientId;
    lastTransactionId = transactionId;
    return linksResult ??
        Success(
          CompanyDocument(
            id: documentId,
            companyId: companyId,
            title: 'Doc',
            originalFileName: 'a.pdf',
            storagePath: '$companyId/$documentId/o.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 1,
            isArchived: false,
            createdAt: DateTime.utc(2026, 7, 1),
            updatedAt: DateTime.utc(2026, 7, 1),
            clientId: clientId,
            transactionId: transactionId,
          ),
        );
  }

  @override
  Future<Result<void>> deleteDocumentPermanently({
    required String companyId,
    required String documentId,
  }) async {
    deleteCalls++;
    return deleteResult ?? const Success(null);
  }
}

void main() {
  group('UpdateDocumentLinks', () {
    test('normalizza id vuoti a null e aggiorna', () async {
      final repo = _Repo();
      final useCase = UpdateDocumentLinks(repo);
      final result = await useCase(
        companyId: 'c1',
        documentId: 'd1',
        clientId: '  ',
        transactionId: ' t1 ',
      );
      expect(result.isSuccess, isTrue);
      expect(repo.lastClientId, isNull);
      expect(repo.lastTransactionId, 't1');
    });

    test('propaga errore FK/tenant', () async {
      final repo = _Repo()
        ..linksResult = const Error(
          ValidationFailure(
            'Cliente non trovato o appartenente a un\'altra azienda.',
          ),
        );
      final useCase = UpdateDocumentLinks(repo);
      final result = await useCase(
        companyId: 'c1',
        documentId: 'd1',
        clientId: 'other',
        transactionId: null,
      );
      expect(result.isError, isTrue);
    });
  });

  group('DeleteDocumentPermanently', () {
    test('successo e retry', () async {
      final repo = _Repo();
      final useCase = DeleteDocumentPermanently(repo);
      expect(
        (await useCase(companyId: 'c1', documentId: 'd1')).isSuccess,
        isTrue,
      );
      expect(
        (await useCase(companyId: 'c1', documentId: 'd1')).isSuccess,
        isTrue,
      );
      expect(repo.deleteCalls, 2);
    });

    test('errore incompleto', () async {
      final repo = _Repo()
        ..deleteResult = const Error(IncompleteDocumentDeletionFailure());
      final useCase = DeleteDocumentPermanently(repo);
      final result = await useCase(companyId: 'c1', documentId: 'd1');
      result.when(
        success: (_) => fail('expected error'),
        error: (failure) =>
            expect(failure, isA<IncompleteDocumentDeletionFailure>()),
      );
    });
  });
}
