import 'dart:typed_data';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../entities/company_document.dart';
import '../repositories/document_repository.dart';
import '../services/document_file_validator.dart';
import '../value_objects/document_file_rules.dart';

class GetDocuments {
  const GetDocuments(this._repository);

  final DocumentRepository _repository;

  Future<Result<List<CompanyDocument>>> call({required String companyId}) {
    return _repository.getDocuments(companyId: companyId);
  }
}

class UploadDocument {
  const UploadDocument(this._repository);

  final DocumentRepository _repository;

  Future<Result<CompanyDocument>> call({
    required String companyId,
    required String title,
    required String originalFileName,
    required String? declaredMimeType,
    required Uint8List? bytes,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty ||
        normalizedTitle.length > DocumentFileRules.maxTitleLength) {
      return const Error(ValidationFailure('Il titolo non è valido.'));
    }

    final normalizedOriginal = originalFileName.trim();
    if (normalizedOriginal.isEmpty ||
        normalizedOriginal.length >
            DocumentFileRules.maxOriginalFileNameLength) {
      return const Error(ValidationFailure('Tipo di file non consentito.'));
    }

    final validation = DocumentFileValidator.validate(
      fileName: normalizedOriginal,
      declaredMimeType: declaredMimeType,
      bytes: bytes,
    );

    switch (validation) {
      case DocumentFileValidationFailure(:final message):
        return Error(ValidationFailure(message));
      case DocumentFileValidationSuccess(
        :final mimeType,
        :final canonicalExtension,
        :final bytes,
      ):
        return _repository.uploadDocument(
          companyId: companyId,
          title: normalizedTitle,
          originalFileName: normalizedOriginal,
          mimeType: mimeType,
          canonicalExtension: canonicalExtension,
          bytes: bytes,
        );
    }
  }
}

class CreateDocumentSignedUrl {
  const CreateDocumentSignedUrl(this._repository);

  final DocumentRepository _repository;

  Future<Result<String>> call({
    required String companyId,
    required String documentId,
  }) {
    return _repository.createSignedUrl(
      companyId: companyId,
      documentId: documentId,
    );
  }
}

class UpdateDocumentTitle {
  const UpdateDocumentTitle(this._repository);

  final DocumentRepository _repository;

  Future<Result<CompanyDocument>> call({
    required String companyId,
    required String documentId,
    required String title,
  }) {
    final normalized = title.trim();
    if (normalized.isEmpty ||
        normalized.length > DocumentFileRules.maxTitleLength) {
      return Future.value(
        const Error(ValidationFailure('Il titolo non è valido.')),
      );
    }
    return _repository.updateTitle(
      companyId: companyId,
      documentId: documentId,
      title: normalized,
    );
  }
}

class SetDocumentArchived {
  const SetDocumentArchived(this._repository);

  final DocumentRepository _repository;

  Future<Result<CompanyDocument>> call({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) {
    return _repository.setArchived(
      companyId: companyId,
      documentId: documentId,
      isArchived: isArchived,
    );
  }
}
