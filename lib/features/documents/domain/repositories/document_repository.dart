import '../../../../core/utils/result.dart';
import '../entities/company_document.dart';

abstract class DocumentRepository {
  Future<Result<List<CompanyDocument>>> getDocuments({
    required String companyId,
  });

  Future<Result<CompanyDocument>> uploadDocument({
    required String companyId,
    required String title,
    required String originalFileName,
    required String mimeType,
    required String canonicalExtension,
    required List<int> bytes,
  });

  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  });

  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  });

  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  });
}
