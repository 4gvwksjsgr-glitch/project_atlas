import 'dart:typed_data';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../subscription/domain/usecases/get_company_subscription_overview.dart';
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
  const UploadDocument(this._repository, this._getOverview);

  final DocumentRepository _repository;
  final GetCompanySubscriptionOverview _getOverview;

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
        final overviewResult = await _getOverview.call(companyId: companyId);
        switch (overviewResult) {
          case Error(:final failure):
            return Error(failure);
          case Success(:final value):
            if (!value.isUnlimited) {
              final limit = value.documentMonthlyLimit;
              if (limit != null && value.documentsUsed >= limit) {
                return const Error(DocumentQuotaExceededFailure());
              }
            }
        }

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

class UpdateDocumentLinks {
  const UpdateDocumentLinks(this._repository);

  final DocumentRepository _repository;

  Future<Result<CompanyDocument>> call({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) {
    final normalizedCompanyId = companyId.trim();
    final normalizedDocumentId = documentId.trim();
    if (normalizedCompanyId.isEmpty || normalizedDocumentId.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Documento non trovato.')),
      );
    }

    final normalizedClientId = _normalizeOptionalId(clientId);
    final normalizedTransactionId = _normalizeOptionalId(transactionId);

    return _repository.updateDocumentLinks(
      companyId: normalizedCompanyId,
      documentId: normalizedDocumentId,
      clientId: normalizedClientId,
      transactionId: normalizedTransactionId,
    );
  }

  static String? _normalizeOptionalId(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class DeleteDocumentPermanently {
  const DeleteDocumentPermanently(this._repository);

  final DocumentRepository _repository;

  Future<Result<void>> call({
    required String companyId,
    required String documentId,
  }) {
    final normalizedCompanyId = companyId.trim();
    final normalizedDocumentId = documentId.trim();
    if (normalizedCompanyId.isEmpty || normalizedDocumentId.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Documento non trovato.')),
      );
    }
    return _repository.deleteDocumentPermanently(
      companyId: normalizedCompanyId,
      documentId: normalizedDocumentId,
    );
  }
}
