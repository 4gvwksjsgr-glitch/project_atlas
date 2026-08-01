import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/subscription_error_mapper.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/subscription/data/models/company_subscription_overview_model.dart';
import 'package:project_atlas/features/subscription/domain/entities/company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:project_atlas/features/subscription/domain/usecases/get_company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:project_atlas/features/subscription/presentation/widgets/company_plan_card.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('CompanySubscriptionOverviewModel', () {
    test('maps Free', () {
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
      expect(entity.isEffectiveUnlimited, isFalse);
      expect(entity.isTrialActive, isFalse);
    });

    test('maps Premium unlimited', () {
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
      expect(entity.isEffectiveUnlimited, isTrue);
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
      }).toEntity();

      expect(entity.isTrialActive, isTrue);
      expect(entity.trialEndsAt, isNotNull);
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

    test('not found maps', () {
      final failure = SubscriptionErrorMapper.mapException(
        const PostgrestException(
          message: 'Subscription not found',
          code: 'P0002',
        ),
      );
      expect(failure, isA<SubscriptionNotFoundFailure>());
    });

    test('plan not found maps without Free/Premium fallback', () {
      final failure = SubscriptionErrorMapper.mapException(
        const PostgrestException(message: 'Plan not found', code: 'P0002'),
      );
      expect(failure, isA<SubscriptionPlanNotFoundFailure>());
      expect(failure.message.toLowerCase(), isNot(contains('free')));
      expect(failure.message.toLowerCase(), isNot(contains('premium')));
      expect(failure.message, isNot(contains('30')));
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
    testWidgets('mostra Free senza contatore x di 30', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              return _sampleFree();
            }),
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

      expect(find.text('Piano e utilizzo'), findsOneWidget);
      expect(find.text('Piano Free'), findsOneWidget);
      expect(find.text('30 documenti al mese'), findsOneWidget);
      expect(find.textContaining('di 30'), findsNothing);
      expect(find.textContaining('Avvia'), findsNothing);
      expect(find.textContaining('Checkout'), findsNothing);
    });

    testWidgets('mostra Premium illimitato', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
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
              );
            }),
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

      expect(find.text('Piano Premium'), findsOneWidget);
      expect(find.text('Documenti illimitati'), findsOneWidget);
      expect(find.textContaining('di 30'), findsNothing);
    });

    testWidgets('trial scaduto mostra effective Free', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              return CompanySubscriptionOverview(
                companyId: 'c1',
                configuredPlanCode: 'premium',
                configuredPlanName: 'Premium',
                status: SubscriptionStatus.trialing,
                effectivePlanCode: 'free',
                effectivePlanName: 'Free',
                documentMonthlyLimit: 30,
                trialStartedAt: DateTime.utc(2026, 5, 1),
                trialEndsAt: DateTime.utc(2026, 6, 1),
                trialUsedAt: DateTime.utc(2026, 5, 1),
                isTrialActive: false,
              );
            }),
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

      expect(find.text('Piano Free'), findsOneWidget);
      expect(find.text('30 documenti al mese'), findsOneWidget);
      expect(find.text('Prova Premium'), findsNothing);
      expect(find.textContaining('Avvia'), findsNothing);
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

    testWidgets('trial attivo mostra scadenza', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
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
              );
            }),
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

      expect(find.text('Prova Premium'), findsOneWidget);
      expect(find.text('Documenti illimitati'), findsOneWidget);
      expect(find.textContaining('Prova valida fino'), findsOneWidget);
    });
  });
}

CompanySubscriptionOverview _sampleFree() {
  return const CompanySubscriptionOverview(
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
  );
}

class _FakeRepo implements SubscriptionRepository {
  _FakeRepo({this.overview});

  final CompanySubscriptionOverview? overview;

  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    return Success(overview ?? _sampleFree());
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
}
