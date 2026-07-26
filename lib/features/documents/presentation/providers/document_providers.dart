import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/document_remote_datasource.dart';
import '../../data/repositories/document_repository_impl.dart';
import '../../data/services/url_launcher_document_url_launcher.dart';
import '../../domain/entities/company_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../../domain/services/document_url_launcher.dart';
import '../../domain/usecases/document_usecases.dart';

final documentRemoteDataSourceProvider = Provider<DocumentRemoteDataSource>((
  ref,
) {
  return DocumentRemoteDataSource(ref.watch(supabaseClientProvider));
});

final documentStorageDataSourceProvider = Provider<DocumentStorageDataSource>((
  ref,
) {
  return DocumentStorageDataSource(ref.watch(supabaseClientProvider));
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepositoryImpl(
    ref.watch(documentRemoteDataSourceProvider),
    ref.watch(documentStorageDataSourceProvider),
  );
});

final documentUrlLauncherProvider = Provider<DocumentUrlLauncher>((ref) {
  return UrlLauncherDocumentUrlLauncher();
});

final getDocumentsUseCaseProvider = Provider<GetDocuments>((ref) {
  return GetDocuments(ref.watch(documentRepositoryProvider));
});

final uploadDocumentUseCaseProvider = Provider<UploadDocument>((ref) {
  return UploadDocument(ref.watch(documentRepositoryProvider));
});

final createDocumentSignedUrlUseCaseProvider =
    Provider<CreateDocumentSignedUrl>((ref) {
      return CreateDocumentSignedUrl(ref.watch(documentRepositoryProvider));
    });

final updateDocumentTitleUseCaseProvider = Provider<UpdateDocumentTitle>((ref) {
  return UpdateDocumentTitle(ref.watch(documentRepositoryProvider));
});

final setDocumentArchivedUseCaseProvider = Provider<SetDocumentArchived>((ref) {
  return SetDocumentArchived(ref.watch(documentRepositoryProvider));
});

final documentsProvider = FutureProvider.autoDispose
    .family<List<CompanyDocument>, String>((ref, companyId) async {
      final result = await ref
          .read(getDocumentsUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (documents) => documents,
        error: (failure) => throw StateError(failure.message),
      );
    });
