import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/errors/document_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/company_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../../domain/value_objects/document_file_rules.dart';
import '../datasource/document_remote_datasource.dart';

class DocumentRepositoryImpl implements DocumentRepository {
  DocumentRepositoryImpl(this._remote, this._storage, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final DocumentRemoteDataSource _remote;
  final DocumentStorageDataSource _storage;
  final Uuid _uuid;

  @override
  Future<Result<List<CompanyDocument>>> getDocuments({
    required String companyId,
  }) async {
    try {
      final rows = await _remote.getDocuments(companyId: companyId);
      return Success(rows.map((row) => row.toEntity()).toList());
    } catch (error) {
      return Error(
        DocumentErrorMapper.mapException(error, DocumentOperation.getDocuments),
      );
    }
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
    final documentId = _uuid.v4();
    final objectId = _uuid.v4();
    final storagePath = '$companyId/$documentId/$objectId.$canonicalExtension';
    final typedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    try {
      await _storage.uploadObject(
        path: storagePath,
        bytes: typedBytes,
        mimeType: mimeType,
      );
    } catch (error) {
      return Error(
        DocumentErrorMapper.mapException(
          error,
          DocumentOperation.uploadDocument,
        ),
      );
    }

    try {
      final model = await _remote.insertDocument(
        id: documentId,
        companyId: companyId,
        title: title,
        originalFileName: originalFileName,
        storagePath: storagePath,
        mimeType: mimeType,
        sizeBytes: typedBytes.length,
      );
      return Success(model.toEntity());
    } catch (error) {
      final primary = DocumentErrorMapper.mapException(
        error,
        DocumentOperation.uploadDocument,
      );
      try {
        await _storage.deleteObject(storagePath);
      } catch (cleanupError) {
        developer.log(
          'Document storage cleanup failed',
          name: 'DocumentRepositoryImpl',
          error: cleanupError,
        );
      }
      return Error(primary);
    }
  }

  @override
  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  }) async {
    try {
      final document = await _remote.getDocument(
        companyId: companyId,
        documentId: documentId,
      );
      if (document.companyId != companyId) {
        return const Error(ValidationFailure('Documento non trovato.'));
      }
      final url = await _storage.createSignedUrl(
        path: document.storagePath,
        expiresIn: DocumentFileRules.signedUrlTtlSeconds,
      );
      return Success(url);
    } catch (error) {
      return Error(
        DocumentErrorMapper.mapException(
          error,
          DocumentOperation.createSignedUrl,
        ),
      );
    }
  }

  @override
  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  }) async {
    try {
      final model = await _remote.updateDocument(
        companyId: companyId,
        documentId: documentId,
        title: title,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        DocumentErrorMapper.mapException(error, DocumentOperation.updateTitle),
      );
    }
  }

  @override
  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) async {
    try {
      final model = await _remote.updateDocument(
        companyId: companyId,
        documentId: documentId,
        isArchived: isArchived,
      );
      return Success(model.toEntity());
    } catch (error) {
      return Error(
        DocumentErrorMapper.mapException(error, DocumentOperation.setArchived),
      );
    }
  }
}
