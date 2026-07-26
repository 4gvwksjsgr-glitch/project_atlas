import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../providers/document_providers.dart';

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

  Future<bool> upload({
    required String title,
    required String originalFileName,
    required String? declaredMimeType,
    required Uint8List? bytes,
  }) async {
    if (state.isLoading) {
      return false;
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

  void clearFeedback() {
    state = const DocumentMutationState();
  }
}

final documentMutationControllerProvider = NotifierProvider.autoDispose
    .family<DocumentMutationController, DocumentMutationState, String>(
      DocumentMutationController.new,
    );
