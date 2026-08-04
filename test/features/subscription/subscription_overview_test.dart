import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/atlas_error_codes.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/subscription_error_mapper.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/subscription/data/models/company_subscription_overview_model.dart';
import 'package:project_atlas/features/subscription/domain/entities/company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:project_atlas/features/subscription/domain/usecases/activate_company_premium_trial.dart';
import 'package:project_atlas/features/subscription/domain/usecases/get_company_subscription_overview.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/subscription/presentation/controllers/activate_premium_trial_controller.dart';
import 'package:project_atlas/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:project_atlas/features/subscription/presentation/widgets/company_plan_card.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('CompanySubscriptionOverviewModel', () {
    test('maps Free 14A without new fields', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        'company_id': 'c1',
        'configured_plan_code': 'free',
        'configured_plan_name': 'Free',
        'subscription_status': 'free',
        'effective_plan_code': 'free',
        'effective_plan_name': 'Free',
        'document_monthly_limit': 30,
        'trial_started_at': null,
        'trial_ends_at': null,
        'trial_used_at': null,
        'is_trial_active': false,
      }).toEntity();

      expect(entity.status, SubscriptionStatus.free);
      expect(entity.documentMonthlyLimit, 30);
      expect(entity.documentsUsed, 0);
      expect(entity.periodStart, isNull);
      expect(entity.periodEnd, isNull);
      expect(entity.isUnlimited, isFalse);
      expect(entity.canActivateTrial, isFalse);
      expect(entity.isEffectiveUnlimited, isFalse);
      expect(entity.isTrialActive, isFalse);
      expect(entity.entitlementOrigin, EntitlementOrigin.none);
      expect(entity.billingSubscriptionStatus, BillingSubscriptionStatus.none);
      expect(entity.syncStatus, BillingSyncStatus.idle);
      expect(entity.canOpenBillingPortal, isFalse);
      expect(entity.billingSyncPending, isFalse);
    });

    test('maps Premium unlimited 14A deriving isUnlimited', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        'company_id': 'c1',
        'configured_plan_code': 'premium',
        'configured_plan_name': 'Premium',
        'subscription_status': 'active',
        'effective_plan_code': 'premium',
        'effective_plan_name': 'Premium',
        'document_monthly_limit': null,
        'is_trial_active': false,
      }).toEntity();

      expect(entity.isEffectivePremium, isTrue);
      expect(entity.isUnlimited, isTrue);
      expect(entity.isEffectiveUnlimited, isTrue);
    });

    test('maps 14B payload complete', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        'company_id': 'c1',
        'configured_plan_code': 'free',
        'configured_plan_name': 'Free',
        'subscription_status': 'free',
        'effective_plan_code': 'free',
        'effective_plan_name': 'Free',
        'document_monthly_limit': 30,
        'is_trial_active': false,
        'documents_used': 12,
        'period_start': '2026-08-01T00:00:00Z',
        'period_end': '2026-09-01T00:00:00Z',
        'is_unlimited': false,
        'can_activate_trial': true,
      }).toEntity();

      expect(entity.documentsUsed, 12);
      expect(entity.periodStart, DateTime.utc(2026, 8, 1));
      expect(entity.periodEnd, DateTime.utc(2026, 9, 1));
      expect(entity.isUnlimited, isFalse);
      expect(entity.canActivateTrial, isTrue);
      expect(entity.entitlementOrigin, EntitlementOrigin.none);
      expect(entity.canOpenBillingPortal, isFalse);
    });

    test('maps 14C-1 payload complete', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        ..._baseJson(),
        'documents_used': 3,
        'period_start': '2026-08-01T00:00:00Z',
        'period_end': '2026-09-01T00:00:00Z',
        'is_unlimited': false,
        'can_activate_trial': false,
        'entitlement_origin': 'provider',
        'billing_subscription_status': 'active',
        'billing_payment_status': 'past_due',
        'sync_status': 'reconcile_required',
        'last_sync_result': 'failed',
        'cancel_at_period_end': true,
        'billing_period_start': '2026-08-01T00:00:00Z',
        'billing_period_end': '2026-09-01T00:00:00Z',
        'provider_access_status': 'grace',
        'provider_access_ends_at': null,
        'is_provider_grace': true,
        'grace_ends_at': '2026-08-10T00:00:00Z',
        'has_payment_issue': true,
        'billing_linked': true,
        'can_open_billing_portal': false,
        'billing_sync_pending': true,
      }).toEntity();

      expect(entity.entitlementOrigin, EntitlementOrigin.provider);
      expect(entity.billingSubscriptionStatus, BillingSubscriptionStatus.active);
      expect(entity.billingPaymentStatus, BillingPaymentStatus.pastDue);
      expect(entity.syncStatus, BillingSyncStatus.reconcileRequired);
      expect(entity.lastSyncResult, BillingLastSyncResult.failed);
      expect(entity.cancelAtPeriodEnd, isTrue);
      expect(entity.providerAccessStatus, ProviderAccessStatus.grace);
      expect(entity.isProviderGrace, isTrue);
      expect(entity.hasPaymentIssue, isTrue);
      expect(entity.billingLinked, isTrue);
      expect(entity.canOpenBillingPortal, isFalse);
      expect(entity.billingSyncPending, isTrue);
    });

    test('unknown billing enums fall back safely', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        ..._baseJson(),
        'entitlement_origin': 'weird_origin',
        'billing_subscription_status': 'weird_sub',
        'billing_payment_status': 'weird_pay',
        'sync_status': 'weird_sync',
        'last_sync_result': 'weird_result',
        'provider_access_status': 'weird_access',
      }).toEntity();

      expect(entity.entitlementOrigin, EntitlementOrigin.unknown);
      expect(entity.billingSubscriptionStatus, BillingSubscriptionStatus.unknown);
      expect(entity.billingPaymentStatus, BillingPaymentStatus.unknown);
      expect(entity.syncStatus, BillingSyncStatus.unknown);
      expect(entity.lastSyncResult, BillingLastSyncResult.unknown);
      expect(entity.providerAccessStatus, ProviderAccessStatus.unknown);
    });

    test('documents_used accepts num and string', () {
      final asNum = CompanySubscriptionOverviewModel.fromJson({
        ..._baseJson(),
        'documents_used': 7.0,
      }).toEntity();
      final asString = CompanySubscriptionOverviewModel.fromJson({
        ..._baseJson(),
        'documents_used': '9',
      }).toEntity();
      expect(asNum.documentsUsed, 7);
      expect(asString.documentsUsed, 9);
    });

    test('maps trial active', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        'company_id': 'c1',
        'configured_plan_code': 'premium',
        'configured_plan_name': 'Premium',
        'subscription_status': 'trialing',
        'effective_plan_code': 'premium',
        'effective_plan_name': 'Premium',
        'document_monthly_limit': null,
        'trial_started_at': '2026-07-01T00:00:00Z',
        'trial_ends_at': '2026-08-01T00:00:00Z',
        'trial_used_at': '2026-07-01T00:00:00Z',
        'is_trial_active': true,
        'is_unlimited': true,
        'can_activate_trial': false,
      }).toEntity();

      expect(entity.isTrialActive, isTrue);
      expect(entity.trialEndsAt, isNotNull);
      expect(entity.canActivateTrial, isFalse);
    });

    test('maps unknown status without crash', () {
      final entity = CompanySubscriptionOverviewModel.fromJson({
        'company_id': 'c1',
        'configured_plan_code': 'free',
        'configured_plan_name': 'Free',
        'subscription_status': 'weird',
        'effective_plan_code': 'free',
        'effective_plan_name': 'Free',
        'document_monthly_limit': 30,
        'is_trial_active': false,
      }).toEntity();

      expect(entity.status, SubscriptionStatus.unknown);
    });

    test('invalid payload throws', () {
      expect(
        () => CompanySubscriptionOverviewModel.fromJson({'company_id': 'c1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AtlasErrorCodes + SubscriptionErrorMapper', () {
    test('extracts from message', () {
      expect(
        AtlasErrorCodes.extract(
          const PostgrestException(
            message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
            code: 'P0001',
          ),
        ),
        AtlasErrorCodes.documentQuotaExceeded,
      );
    });

    test('extracts from details', () {
      expect(
        AtlasErrorCodes.extract(
          const PostgrestException(
            message: 'raise exception',
            details: 'ATLAS_TRIAL_ALREADY_USED detail',
            code: 'P0001',
          ),
        ),
        AtlasErrorCodes.trialAlreadyUsed,
      );
    });

    test('extracts from hint', () {
      expect(
        AtlasErrorCodes.extract(
          const PostgrestException(
            message: 'error',
            hint: 'see ATLAS_ALREADY_PREMIUM',
            code: 'P0001',
          ),
        ),
        AtlasErrorCodes.alreadyPremium,
      );
    });

    for (final entry in <String, Type>{
      AtlasErrorCodes.documentQuotaExceeded: DocumentQuotaExceededFailure,
      AtlasErrorCodes.subscriptionNotFound: SubscriptionNotFoundFailure,
      AtlasErrorCodes.planNotFound: SubscriptionPlanNotFoundFailure,
      AtlasErrorCodes.companyIdRequired: AtlasCompanyIdRequiredFailure,
      AtlasErrorCodes.notCompanyOwner: AtlasNotCompanyOwnerFailure,
      AtlasErrorCodes.trialAlreadyActive: AtlasTrialAlreadyActiveFailure,
      AtlasErrorCodes.alreadyPremium: AtlasAlreadyPremiumFailure,
      AtlasErrorCodes.trialAlreadyUsed: AtlasTrialAlreadyUsedFailure,
      AtlasErrorCodes.premiumUnavailable: AtlasPremiumUnavailableFailure,
      AtlasErrorCodes.billingLinked: AtlasBillingLinkedFailure,
      AtlasErrorCodes.billingSyncPending: AtlasBillingSyncPendingFailure,
    }.entries) {
      test('maps ${entry.key}', () {
        final failure = SubscriptionErrorMapper.mapException(
          PostgrestException(message: entry.key, code: 'P0001'),
          SubscriptionOperation.activatePremiumTrial,
        );
        expect(failure.runtimeType, entry.value);
      });
    }

    test('quota and trial codes do not collide', () {
      final quota = SubscriptionErrorMapper.mapException(
        const PostgrestException(
          message: 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
          code: 'P0001',
        ),
      );
      final trial = SubscriptionErrorMapper.mapException(
        const PostgrestException(
          message: 'ATLAS_TRIAL_ALREADY_ACTIVE',
          code: 'P0001',
        ),
      );
      expect(quota, isA<DocumentQuotaExceededFailure>());
      expect(trial, isA<AtlasTrialAlreadyActiveFailure>());
      expect(quota.message, isNot(trial.message));
    });

    test('unknown falls back', () {
      final failure = SubscriptionErrorMapper.mapException(
        Exception('something weird'),
        SubscriptionOperation.activatePremiumTrial,
      );
      expect(failure, isA<UnknownFailure>());
    });

    test('legacy plan not found still maps', () {
      final failure = SubscriptionErrorMapper.mapException(
        const PostgrestException(message: 'Plan not found', code: 'P0002'),
      );
      expect(failure, isA<SubscriptionPlanNotFoundFailure>());
      expect(failure.message.toLowerCase(), isNot(contains('free')));
      expect(failure.message.toLowerCase(), isNot(contains('premium')));
      expect(failure.message, isNot(contains('30')));
    });
  });

  group('GetCompanySubscriptionOverview', () {
    test('empty companyId → validation', () async {
      final result = await GetCompanySubscriptionOverview(
        _FakeRepo(),
      ).call(companyId: '  ');
      expect(result.isError, isTrue);
    });

    test('success', () async {
      final result = await GetCompanySubscriptionOverview(
        _FakeRepo(overview: _sampleFree()),
      ).call(companyId: 'c1');
      expect(result.isSuccess, isTrue);
    });
  });

  group('ActivateCompanyPremiumTrial', () {
    test('RPC success void', () async {
      final repo = _FakeRepo();
      final result = await ActivateCompanyPremiumTrial(
        repo,
      ).call(companyId: 'c1');
      expect(result.isSuccess, isTrue);
      expect(repo.activateCalls, 1);
      expect(repo.lastActivateCompanyId, 'c1');
    });

    test('empty companyId', () async {
      final result = await ActivateCompanyPremiumTrial(
        _FakeRepo(),
      ).call(companyId: ' ');
      expect(result.isError, isTrue);
      expect(result, isA<Error<void>>());
      result.when(
        success: (_) => fail('expected error'),
        error: (f) => expect(f, isA<AtlasCompanyIdRequiredFailure>()),
      );
    });

    test('owner failure', () async {
      final result = await ActivateCompanyPremiumTrial(
        _FakeRepo(activateFailure: const AtlasNotCompanyOwnerFailure()),
      ).call(companyId: 'c1');
      expect(result.isError, isTrue);
    });
  });

  group('ActivatePremiumTrialController', () {
    test('success refreshes overview and ignores double tap', () async {
      final repo = _FakeRepo(
        overview: _sampleFree(canActivateTrial: true),
        activateOverviewAfter: _sampleTrialActive(),
      );
      final container = ProviderContainer(
        overrides: [subscriptionRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        activatePremiumTrialControllerProvider('c1').notifier,
      );

      final first = notifier.activate();
      final second = notifier.activate();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.activateCalls, 1);
      expect(
        container
            .read(activatePremiumTrialControllerProvider('c1'))
            .actionStatus,
        CompanyActionStatus.success,
      );
      final overview = await container.read(
        companySubscriptionOverviewProvider('c1').future,
      );
      expect(overview.isTrialActive, isTrue);
    });

    test('trial already active maps error', () async {
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(
            _FakeRepo(activateFailure: const AtlasTrialAlreadyActiveFailure()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(activatePremiumTrialControllerProvider('c1').notifier)
          .activate();
      expect(ok, isFalse);
      expect(
        container
            .read(activatePremiumTrialControllerProvider('c1'))
            .errorMessage,
        'La prova Premium è già attiva.',
      );
    });
  });

  group('companySubscriptionOverviewProvider', () {
    test('isolates tenants', () async {
      final container = ProviderContainer(
        overrides: [
          getCompanySubscriptionOverviewUseCaseProvider.overrideWithValue(
            GetCompanySubscriptionOverview(_TenantAwareRepo()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final a = await container.read(
        companySubscriptionOverviewProvider('aaa').future,
      );
      final b = await container.read(
        companySubscriptionOverviewProvider('bbb').future,
      );
      expect(a.companyId, 'aaa');
      expect(b.companyId, 'bbb');
    });
  });

  group('CompanyPlanCard', () {
    Future<void> pumpCard(
      WidgetTester tester,
      CompanySubscriptionOverview overview, {
      Size? surfaceSize,
    }) async {
      if (surfaceSize != null) {
        await tester.binding.setSurfaceSize(surfaceSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              return overview;
            }),
            activateCompanyPremiumTrialUseCaseProvider.overrideWithValue(
              ActivateCompanyPremiumTrial(_FakeRepo()),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('it'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CompanyPlanCard(companyId: 'c1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Free 0/30', (tester) async {
      await pumpCard(tester, _sampleFree());
      expect(find.text('Piano e utilizzo'), findsOneWidget);
      expect(find.text('Piano Free'), findsOneWidget);
      expect(
        find.text('0 di 30 documenti utilizzati questo mese'),
        findsOneWidget,
      );
      expect(find.text('Attiva la prova Premium'), findsNothing);
      expect(find.textContaining('Checkout'), findsNothing);
    });

    testWidgets('Free 29/30', (tester) async {
      await pumpCard(tester, _sampleFree(documentsUsed: 29));
      expect(
        find.text('29 di 30 documenti utilizzati questo mese'),
        findsOneWidget,
      );
      expect(find.text('Quota mensile esaurita'), findsNothing);
    });

    testWidgets('Free 30/30', (tester) async {
      await pumpCard(tester, _sampleFree(documentsUsed: 30));
      expect(find.text('Quota mensile esaurita'), findsOneWidget);
      expect(
        find.text('30 di 30 documenti utilizzati questo mese'),
        findsOneWidget,
      );
    });

    testWidgets('Free usage >30 after expired trial', (tester) async {
      await pumpCard(
        tester,
        _sampleFree(documentsUsed: 45, canActivateTrial: false),
      );
      expect(find.text('Quota mensile esaurita'), findsOneWidget);
      expect(
        find.text('45 di 30 documenti utilizzati questo mese'),
        findsOneWidget,
      );
    });

    testWidgets('Premium illimitato', (tester) async {
      await pumpCard(tester, _samplePremium());
      expect(find.text('Piano Premium'), findsOneWidget);
      expect(find.text('Documenti illimitati'), findsOneWidget);
      expect(find.text('Attiva la prova Premium'), findsNothing);
    });

    testWidgets('trial attiva con data fine', (tester) async {
      await pumpCard(tester, _sampleTrialActive());
      expect(find.text('Prova Premium'), findsOneWidget);
      expect(find.text('Prova Premium attiva'), findsOneWidget);
      expect(find.text('Documenti illimitati'), findsOneWidget);
      expect(find.textContaining('Prova valida fino'), findsOneWidget);
      expect(find.text('Attiva la prova Premium'), findsNothing);
    });

    testWidgets('owner eleggibile vede CTA', (tester) async {
      await pumpCard(tester, _sampleFree(canActivateTrial: true));
      expect(find.text('Attiva la prova Premium'), findsOneWidget);
    });

    testWidgets('admin non vede CTA via canActivateTrial=false', (
      tester,
    ) async {
      await pumpCard(tester, _sampleFree(canActivateTrial: false));
      expect(find.text('Attiva la prova Premium'), findsNothing);
    });

    testWidgets('dialog annullato non attiva', (tester) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              return _sampleFree(canActivateTrial: true);
            }),
            subscriptionRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('it'),
            home: Scaffold(body: CompanyPlanCard(companyId: 'c1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attiva la prova Premium'));
      await tester.pumpAndSettle();
      expect(find.text('Attivare la prova Premium?'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(repo.activateCalls, 0);
    });

    testWidgets('dialog confermato attiva trial', (tester) async {
      final repo = _FakeRepo(
        overview: _sampleFree(canActivateTrial: true),
        activateOverviewAfter: _sampleTrialActive(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [subscriptionRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('it'),
            home: Scaffold(body: CompanyPlanCard(companyId: 'c1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attiva la prova Premium'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attiva prova'));
      await tester.pumpAndSettle();
      expect(repo.activateCalls, 1);
      expect(find.text('Prova Premium attivata.'), findsOneWidget);
      expect(find.text('Prova Premium attiva'), findsOneWidget);
    });

    testWidgets('viewport Android portrait no overflow', (tester) async {
      await pumpCard(
        tester,
        _sampleFree(canActivateTrial: true, documentsUsed: 12),
        surfaceSize: const Size(360, 740),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('viewport Android landscape no overflow', (tester) async {
      await pumpCard(
        tester,
        _sampleFree(canActivateTrial: true),
        surfaceSize: const Size(800, 360),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Web stretto no overflow', (tester) async {
      await pumpCard(
        tester,
        _sampleTrialActive(),
        surfaceSize: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('errore non crasha e mostra messaggio', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              throw StateError('Caricamento piano non riuscito. Riprova.');
            }),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('it'),
            home: Scaffold(
              body: Column(
                children: [
                  Text('settings-ok'),
                  CompanyPlanCard(companyId: 'c1'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('settings-ok'), findsOneWidget);
      expect(find.textContaining('non riuscito'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _baseJson() => {
  'company_id': 'c1',
  'configured_plan_code': 'free',
  'configured_plan_name': 'Free',
  'subscription_status': 'free',
  'effective_plan_code': 'free',
  'effective_plan_name': 'Free',
  'document_monthly_limit': 30,
  'is_trial_active': false,
};

CompanySubscriptionOverview _sampleFree({
  int documentsUsed = 0,
  bool canActivateTrial = false,
}) {
  return CompanySubscriptionOverview(
    companyId: 'c1',
    configuredPlanCode: 'free',
    configuredPlanName: 'Free',
    status: SubscriptionStatus.free,
    effectivePlanCode: 'free',
    effectivePlanName: 'Free',
    documentMonthlyLimit: 30,
    trialStartedAt: null,
    trialEndsAt: null,
    trialUsedAt: null,
    isTrialActive: false,
    documentsUsed: documentsUsed,
    isUnlimited: false,
    canActivateTrial: canActivateTrial,
  );
}

CompanySubscriptionOverview _samplePremium() {
  return const CompanySubscriptionOverview(
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
    isUnlimited: true,
  );
}

CompanySubscriptionOverview _sampleTrialActive() {
  return CompanySubscriptionOverview(
    companyId: 'c1',
    configuredPlanCode: 'premium',
    configuredPlanName: 'Premium',
    status: SubscriptionStatus.trialing,
    effectivePlanCode: 'premium',
    effectivePlanName: 'Premium',
    documentMonthlyLimit: null,
    trialStartedAt: DateTime.utc(2026, 7, 1),
    trialEndsAt: DateTime.utc(2026, 8, 1),
    trialUsedAt: DateTime.utc(2026, 7, 1),
    isTrialActive: true,
    isUnlimited: true,
    canActivateTrial: false,
  );
}

class _FakeRepo implements SubscriptionRepository {
  _FakeRepo({this.overview, this.activateFailure, this.activateOverviewAfter});

  CompanySubscriptionOverview? overview;
  final Failure? activateFailure;
  final CompanySubscriptionOverview? activateOverviewAfter;
  int activateCalls = 0;
  String? lastActivateCompanyId;

  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    return Success(overview ?? _sampleFree());
  }

  @override
  Future<Result<void>> activateCompanyPremiumTrial({
    required String companyId,
  }) async {
    activateCalls += 1;
    lastActivateCompanyId = companyId;
    if (activateFailure != null) {
      return Error(activateFailure!);
    }
    if (activateOverviewAfter != null) {
      overview = activateOverviewAfter;
    }
    return const Success(null);
  }
}

class _TenantAwareRepo implements SubscriptionRepository {
  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    return Success(
      CompanySubscriptionOverview(
        companyId: companyId,
        configuredPlanCode: 'free',
        configuredPlanName: 'Free',
        status: SubscriptionStatus.free,
        effectivePlanCode: 'free',
        effectivePlanName: 'Free',
        documentMonthlyLimit: 30,
        trialStartedAt: null,
        trialEndsAt: null,
        trialUsedAt: null,
        isTrialActive: false,
      ),
    );
  }

  @override
  Future<Result<void>> activateCompanyPremiumTrial({
    required String companyId,
  }) async {
    return const Success(null);
  }
}
