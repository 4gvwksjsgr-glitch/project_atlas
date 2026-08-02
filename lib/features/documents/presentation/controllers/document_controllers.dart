import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../providers/document_providers.dart';

/// Esito immutabile di [DocumentUploadController.upload].
///
/// La UI deve usare questo valore per lo SnackBar: non rileggere lo stato
/// del provider `autoDispose` dopo l'`await`.
final class DocumentUploadOutcome {
  const DocumentUploadOutcome._({required this.isSuccess, this.failure});

  const DocumentUploadOutcome.success() : this._(isSuccess: true);

  const DocumentUploadOutcome.failure(Failure failure)
    : this._(isSuccess: false, failure: failure);

  /// Chiamata ignorata (anti-doppio tap mentre è già in corso un upload).
  const DocumentUploadOutcome.ignored() : this._(isSuccess: false);

  final bool isSuccess;
  final Failure? failure;
}

class DocumentUploadState {
  const DocumentUploadState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  DocumentUploadState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentUploadState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class DocumentUploadController
    extends AutoDisposeFamilyNotifier<DocumentUploadState, String> {
  @override
  DocumentUploadState build(String companyId) {
    return const DocumentUploadState();
  }

  Future<DocumentUploadOutcome> upload({
    required String title,
    required String originalFileName,
    required String? declaredMimeType,
    required Uint8List? bytes,
  }) async {
    if (state.isLoading) {
      return const DocumentUploadOutcome.ignored();
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(uploadDocumentUseCaseProvider)
        .call(
          companyId: arg,
          title: title,
          originalFileName: originalFileName,
          declaredMimeType: declaredMimeType,
          bytes: bytes,
        );

    return result.when(
      success: (_) {
        ref.invalidate(documentsProvider(arg));
        ref.invalidate(companySubscriptionOverviewProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return const DocumentUploadOutcome.success();
      },
      error: (failure) {
        ref.invalidate(companySubscriptionOverviewProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return DocumentUploadOutcome.failure(failure);
      },
    );
  }

  void clearFeedback() {
    state = const DocumentUploadState();
  }
}

final documentUploadControllerProvider = NotifierProvider.autoDispose
    .family<DocumentUploadController, DocumentUploadState, String>(
      DocumentUploadController.new,
    );

class DocumentMutationState {
  const DocumentMutationState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  DocumentMutationState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentMutationState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class DocumentMutationController
    extends AutoDisposeFamilyNotifier<DocumentMutationState, String> {
  @override
  DocumentMutationState build(String companyId) {
    return const DocumentMutationState();
  }

  Future<bool> rename({
    required String documentId,
    required String title,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );
    final result = await ref
        .read(updateDocumentTitleUseCaseProvider)
        .call(companyId: arg, documentId: documentId, title: title);
    return result.when(
      success: (_) {
        ref.invalidate(documentsProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  Future<bool> setArchived({
    required String documentId,
    required bool isArchived,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );
    final result = await ref
        .read(setDocumentArchivedUseCaseProvider)
        .call(companyId: arg, documentId: documentId, isArchived: isArchived);
    return result.when(
      success: (_) {
        ref.invalidate(documentsProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  Future<bool> updateLinks({
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );
    final result = await ref
        .read(updateDocumentLinksUseCaseProvider)
        .call(
          companyId: arg,
          documentId: documentId,
          clientId: clientId,
          transactionId: transactionId,
        );
    return result.when(
      success: (_) {
        ref.invalidate(documentsProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  Future<bool> deletePermanently({required String documentId}) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );
    final result = await ref
        .read(deleteDocumentPermanentlyUseCaseProvider)
        .call(companyId: arg, documentId: documentId);
    return result.when(
      success: (_) {
        ref.invalidate(documentsProvider(arg));
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  void clearFeedback() {
    state = const DocumentMutationState();
  }
}

final documentMutationControllerProvider = NotifierProvider.autoDispose
    .family<DocumentMutationController, DocumentMutationState, String>(
      DocumentMutationController.new,
    );
