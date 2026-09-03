import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/exceptions.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/documents/data/datasource/document_remote_datasource.dart';
import 'package:project_atlas/features/documents/data/repositories/document_repository_impl.dart';
import 'package:project_atlas/features/documents/domain/entities/company_document.dart';
import 'package:project_atlas/features/documents/domain/repositories/document_repository.dart';
import 'package:project_atlas/features/documents/domain/usecases/document_usecases.dart';
import 'package:project_atlas/features/documents/presentation/controllers/document_controllers.dart';
import 'package:project_atlas/features/documents/presentation/providers/document_providers.dart';
import 'package:project_atlas/features/subscription/domain/entities/company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/domain/entities/premium_checkout_session.dart';
import 'package:project_atlas/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:project_atlas/features/subscription/domain/usecases/get_company_subscription_overview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

Uint8List _pdfBytes() => Uint8List.fromList(
  '%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF'.codeUnits,
);

void main() {
  group('UploadDocument pre-check quota', () {
    test('Free sotto quota esegue Storage e metadata', () async {
      var uploaded = false;
      var inserted = false;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (payload) async {
            inserted = true;
            return {
              ...payload,
              'uploaded_by': 'u1',
              'is_archived': false,
              'created_at': '2026-08-01T10:00:00Z',
              'updated_at': '2026-08-01T10:00:00Z',
            };
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {
                uploaded = true;
              },
        ),
        uuid: const Uuid(),
      );

      final result =
          await UploadDocument(
            repo,
            GetCompanySubscriptionOverview(
              _OverviewRepo(_freeOverview(used: 5, limit: 30)),
            ),
          ).call(
            companyId: '11111111-1111-1111-1111-111111111111',
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(result.isSuccess, isTrue);
      expect(uploaded, isTrue);
      expect(inserted, isTrue);
    });

    test('quota già raggiunta → nessuna chiamata Storage', () async {
      var uploaded = false;
      final repo = _TrackingRepo(
        onUpload: () {
          uploaded = true;
        },
      );

      final result =
          await UploadDocument(
            repo,
            GetCompanySubscriptionOverview(
              _OverviewRepo(_freeOverview(used: 30, limit: 30)),
            ),
          ).call(
            companyId: 'c1',
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('expected error'),
        error: (f) {
          expect(f, isA<DocumentQuotaExceededFailure>());
          expect(f.message, 'Hai raggiunto il limite di documenti del mese.');
        },
      );
      expect(uploaded, isFalse);
    });

    test('overview fallita → nessuna chiamata Storage', () async {
      var uploaded = false;
      final repo = _TrackingRepo(
        onUpload: () {
          uploaded = true;
        },
      );

      final result =
          await UploadDocument(
            repo,
            GetCompanySubscriptionOverview(
              _OverviewRepo(null, failure: const NetworkFailure()),
            ),
          ).call(
            companyId: 'c1',
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(result.isError, isTrue);
      expect(uploaded, isFalse);
    });

    test('Premium unlimited consente upload', () async {
      var uploaded = false;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (payload) async {
            return {
              ...payload,
              'uploaded_by': 'u1',
              'is_archived': false,
              'created_at': '2026-08-01T10:00:00Z',
              'updated_at': '2026-08-01T10:00:00Z',
            };
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {
                uploaded = true;
              },
        ),
      );

      final result =
          await UploadDocument(
            repo,
            GetCompanySubscriptionOverview(
              _OverviewRepo(
                const CompanySubscriptionOverview(
                  companyId: 'c1',
                  configuredPlanCode: 'premium',
                  configuredPlanName: 'Premium',
                  status: SubscriptionStatus.active,
                  effectivePlanCode: 'premium',
                  effectivePlanName: 'Premium',
                  documentMonthlyLimit: null,
                  trialStartedAt: null,
                  trialEndsAt: null,
                  trialUsedAt: null,
                  isTrialActive: false,
                  documentsUsed: 100,
                  isUnlimited: true,
                ),
              ),
            ),
          ).call(
            companyId: '11111111-1111-1111-1111-111111111111',
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(result.isSuccess, isTrue);
      expect(uploaded, isTrue);
    });
  });

  group('Upload race quota + cleanup', () {
    test('race: metadata ATLAS_DOCUMENT_QUOTA_EXCEEDED + cleanup ok', () async {
      var deleted = false;
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            throw const PostgrestException(
              message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
              code: 'P0001',
            );
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {},
          deleteExecutor: (_) async {
            deleted = true;
            return DocumentStorageDeleteResult.deleted;
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

      expect(deleted, isTrue);
      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('expected error'),
        error: (f) {
          expect(f, isA<DocumentQuotaExceededFailure>());
          expect(f.message, 'Hai raggiunto il limite di documenti del mese.');
        },
      );
    });

    test('race + cleanup fallito → failure parziale', () async {
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            throw const PostgrestException(
              message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
              code: 'P0001',
            );
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

      result.when(
        success: (_) => fail('expected error'),
        error: (f) {
          expect(f, isA<DocumentQuotaExceededCleanupFailedFailure>());
          expect(f.message.toLowerCase(), contains('non è stato rimosso'));
        },
      );
    });

    test('race + delete no-op → failure parziale', () async {
      final repo = DocumentRepositoryImpl(
        DocumentRemoteDataSource.test(
          insertExecutor: (_) async {
            throw const PostgrestException(
              message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
              details: 'company=x',
              code: 'P0001',
            );
          },
        ),
        DocumentStorageDataSource.test(
          uploadExecutor:
              ({required path, required bytes, required mimeType}) async {},
          deleteExecutor: (_) async {
            throw const DocumentStorageDeleteNoOpException();
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

      result.when(
        success: (_) => fail('expected error'),
        error: (f) =>
            expect(f, isA<DocumentQuotaExceededCleanupFailedFailure>()),
      );
    });

    test('insert fallito non-quota conserva errore primario', () async {
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

      result.when(
        success: (_) => fail('expected error'),
        error: (f) {
          expect(f, isNot(isA<DocumentQuotaExceededCleanupFailedFailure>()));
          expect(f.message.toLowerCase(), isNot(contains('cleanup')));
        },
      );
    });
  });

  group('DocumentUploadController outcome', () {
    test(
      'pre-check quota → outcome con DocumentQuotaExceededFailure, no Storage',
      () async {
        var uploaded = false;
        final container = ProviderContainer(
          overrides: [
            uploadDocumentUseCaseProvider.overrideWithValue(
              UploadDocument(
                _TrackingRepo(
                  onUpload: () {
                    uploaded = true;
                  },
                ),
                GetCompanySubscriptionOverview(
                  _OverviewRepo(_freeOverview(used: 30, limit: 30)),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final outcome = await container
            .read(documentUploadControllerProvider('c1').notifier)
            .upload(
              title: 'Doc',
              originalFileName: 'doc.pdf',
              declaredMimeType: 'application/pdf',
              bytes: _pdfBytes(),
            );

        expect(outcome.isSuccess, isFalse);
        expect(outcome.failure, isA<DocumentQuotaExceededFailure>());
        expect(
          outcome.failure!.message,
          'Hai raggiunto il limite di documenti del mese.',
        );
        expect(uploaded, isFalse);
      },
    );

    test(
      'outcome non dipende dalla rilettura dello stato autoDispose',
      () async {
        final container = ProviderContainer(
          overrides: [
            uploadDocumentUseCaseProvider.overrideWithValue(
              UploadDocument(
                _TrackingRepo(),
                GetCompanySubscriptionOverview(
                  _OverviewRepo(_freeOverview(used: 30, limit: 30)),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          documentUploadControllerProvider('c1').notifier,
        );
        final outcome = await notifier.upload(
          title: 'Doc',
          originalFileName: 'doc.pdf',
          declaredMimeType: 'application/pdf',
          bytes: _pdfBytes(),
        );

        // Simula dispose/ricreazione post-await (nessun listener sul family).
        container.invalidate(documentUploadControllerProvider('c1'));
        final rebuilt = container.read(documentUploadControllerProvider('c1'));
        expect(rebuilt.errorMessage, isNull);
        expect(rebuilt.actionStatus, CompanyActionStatus.idle);

        expect(outcome.isSuccess, isFalse);
        expect(
          outcome.failure!.message,
          'Hai raggiunto il limite di documenti del mese.',
        );
      },
    );

    test(
      'race cleanup ok → DocumentQuotaExceededFailure nell\'outcome',
      () async {
        final container = ProviderContainer(
          overrides: [
            uploadDocumentUseCaseProvider.overrideWithValue(
              UploadDocument(
                DocumentRepositoryImpl(
                  DocumentRemoteDataSource.test(
                    insertExecutor: (_) async {
                      throw const PostgrestException(
                        message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
                        code: 'P0001',
                      );
                    },
                  ),
                  DocumentStorageDataSource.test(
                    uploadExecutor:
                        ({
                          required path,
                          required bytes,
                          required mimeType,
                        }) async {},
                    deleteExecutor: (_) async {
                      return DocumentStorageDeleteResult.deleted;
                    },
                  ),
                ),
                GetCompanySubscriptionOverview(
                  _OverviewRepo(_freeOverview(used: 0, limit: 30)),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final outcome = await container
            .read(documentUploadControllerProvider('c1').notifier)
            .upload(
              title: 'Doc',
              originalFileName: 'doc.pdf',
              declaredMimeType: 'application/pdf',
              bytes: _pdfBytes(),
            );

        expect(outcome.failure, isA<DocumentQuotaExceededFailure>());
        expect(
          outcome.failure!.message,
          'Hai raggiunto il limite di documenti del mese.',
        );
      },
    );

    test('race cleanup fallito → failure parziale nell\'outcome', () async {
      final container = ProviderContainer(
        overrides: [
          uploadDocumentUseCaseProvider.overrideWithValue(
            UploadDocument(
              DocumentRepositoryImpl(
                DocumentRemoteDataSource.test(
                  insertExecutor: (_) async {
                    throw const PostgrestException(
                      message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
                      code: 'P0001',
                    );
                  },
                ),
                DocumentStorageDataSource.test(
                  uploadExecutor:
                      ({
                        required path,
                        required bytes,
                        required mimeType,
                      }) async {},
                  deleteExecutor: (_) async {
                    throw Exception('cleanup failed');
                  },
                ),
              ),
              GetCompanySubscriptionOverview(
                _OverviewRepo(_freeOverview(used: 0, limit: 30)),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(documentUploadControllerProvider('c1').notifier)
          .upload(
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(outcome.failure, isA<DocumentQuotaExceededCleanupFailedFailure>());
      expect(
        outcome.failure!.message.toLowerCase(),
        contains('non è stato rimosso'),
      );
    });

    test('race delete no-op → failure parziale nell\'outcome', () async {
      final container = ProviderContainer(
        overrides: [
          uploadDocumentUseCaseProvider.overrideWithValue(
            UploadDocument(
              DocumentRepositoryImpl(
                DocumentRemoteDataSource.test(
                  insertExecutor: (_) async {
                    throw const PostgrestException(
                      message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
                      code: 'P0001',
                    );
                  },
                ),
                DocumentStorageDataSource.test(
                  uploadExecutor:
                      ({
                        required path,
                        required bytes,
                        required mimeType,
                      }) async {},
                  deleteExecutor: (_) async {
                    throw const DocumentStorageDeleteNoOpException();
                  },
                ),
              ),
              GetCompanySubscriptionOverview(
                _OverviewRepo(_freeOverview(used: 0, limit: 30)),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(documentUploadControllerProvider('c1').notifier)
          .upload(
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(outcome.failure, isA<DocumentQuotaExceededCleanupFailedFailure>());
    });

    test('successo → outcome isSuccess senza failure', () async {
      final container = ProviderContainer(
        overrides: [
          uploadDocumentUseCaseProvider.overrideWithValue(
            UploadDocument(
              DocumentRepositoryImpl(
                DocumentRemoteDataSource.test(
                  insertExecutor: (payload) async {
                    return {
                      ...payload,
                      'uploaded_by': 'u1',
                      'is_archived': false,
                      'created_at': '2026-08-01T10:00:00Z',
                      'updated_at': '2026-08-01T10:00:00Z',
                    };
                  },
                ),
                DocumentStorageDataSource.test(
                  uploadExecutor:
                      ({
                        required path,
                        required bytes,
                        required mimeType,
                      }) async {},
                ),
                uuid: const Uuid(),
              ),
              GetCompanySubscriptionOverview(
                _OverviewRepo(_freeOverview(used: 1, limit: 30)),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(
            documentUploadControllerProvider(
              '11111111-1111-1111-1111-111111111111',
            ).notifier,
          )
          .upload(
            title: 'Doc',
            originalFileName: 'doc.pdf',
            declaredMimeType: 'application/pdf',
            bytes: _pdfBytes(),
          );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.failure, isNull);
    });
  });
}

CompanySubscriptionOverview _freeOverview({
  required int used,
  required int limit,
}) {
  return CompanySubscriptionOverview(
    companyId: 'c1',
    configuredPlanCode: 'free',
    configuredPlanName: 'Free',
    status: SubscriptionStatus.free,
    effectivePlanCode: 'free',
    effectivePlanName: 'Free',
    documentMonthlyLimit: limit,
    trialStartedAt: null,
    trialEndsAt: null,
    trialUsedAt: null,
    isTrialActive: false,
    documentsUsed: used,
    isUnlimited: false,
  );
}

class _OverviewRepo implements SubscriptionRepository {
  _OverviewRepo(this.overview, {this.failure});

  final CompanySubscriptionOverview? overview;
  final Failure? failure;

  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    if (failure != null) {
      return Error(failure!);
    }
    return Success(overview!);
  }

  @override
  Future<Result<void>> activateCompanyPremiumTrial({
    required String companyId,
  }) async {
    return const Success(null);
  }

  @override
  Future<Result<PremiumCheckoutSession>> createCompanyPremiumCheckout({
    required String companyId,
    required String idempotencyKey,
  }) async {
    return const Error(UnknownFailure('checkout not used in this test'));
  }
}

class _TrackingRepo implements DocumentRepository {
  _TrackingRepo({this.onUpload});

  final void Function()? onUpload;

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
  }) async {
    onUpload?.call();
    return Error(UnknownFailure('should not upload'));
  }

  @override
  Future<Result<String>> createSignedUrl({
    required String companyId,
    required String documentId,
  }) async => const Error(UnknownFailure());

  @override
  Future<Result<CompanyDocument>> updateTitle({
    required String companyId,
    required String documentId,
    required String title,
  }) async => const Error(UnknownFailure());

  @override
  Future<Result<CompanyDocument>> setArchived({
    required String companyId,
    required String documentId,
    required bool isArchived,
  }) async => const Error(UnknownFailure());

  @override
  Future<Result<CompanyDocument>> updateDocumentLinks({
    required String companyId,
    required String documentId,
    required String? clientId,
    required String? transactionId,
  }) async => const Error(UnknownFailure());

  @override
  Future<Result<void>> deleteDocumentPermanently({
    required String companyId,
    required String documentId,
  }) async => const Success(null);
}
