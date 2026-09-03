import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/atlas_error_codes.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/subscription_error_mapper.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/subscription/data/datasource/subscription_remote_datasource.dart';
import 'package:project_atlas/features/subscription/data/models/premium_checkout_session_model.dart';
import 'package:project_atlas/features/subscription/data/repositories/subscription_repository_impl.dart';
import 'package:project_atlas/features/subscription/domain/entities/company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/domain/entities/premium_checkout_session.dart';
import 'package:project_atlas/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:project_atlas/features/subscription/domain/services/billing_checkout_url_launcher.dart';
import 'package:project_atlas/features/subscription/domain/services/sandbox_billing_checkout_url.dart';
import 'package:project_atlas/features/subscription/domain/usecases/create_company_premium_checkout.dart';
import 'package:project_atlas/features/subscription/presentation/controllers/create_premium_checkout_controller.dart';
import 'package:project_atlas/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:project_atlas/features/subscription/presentation/widgets/company_plan_card.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const validCheckoutUrl =
      'https://project-atlas-bxh.pages.dev/billing/checkout'
      '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg';

  Map<String, dynamic> validPayload({String? checkoutUrl}) => {
    'schema_version': 1,
    'checkout_session_id': 'ccs_test_1',
    'checkout_url': checkoutUrl ?? validCheckoutUrl,
    'return_token': 'rt_test_token',
    'return_token_version': 1,
    'expires_at': '2026-08-31T12:00:00Z',
    'reused': false,
  };

  PremiumCheckoutSession sampleSession({String? checkoutUrl}) {
    return PremiumCheckoutSessionModel.fromJson(
      validPayload(checkoutUrl: checkoutUrl),
    ).toEntity();
  }

  group('PremiumCheckoutSessionModel', () {
    test('parses valid success payload', () {
      final entity = PremiumCheckoutSessionModel.fromJson(
        validPayload(),
      ).toEntity();
      expect(entity.checkoutSessionId, 'ccs_test_1');
      expect(entity.checkoutUrl, validCheckoutUrl);
      expect(entity.returnToken, 'rt_test_token');
      expect(entity.returnTokenVersion, 1);
      expect(entity.expiresAt, DateTime.utc(2026, 8, 31, 12));
      expect(entity.reused, isFalse);
    });

    test('fails closed on missing checkout_url', () {
      final json = validPayload()..remove('checkout_url');
      expect(
        () => PremiumCheckoutSessionModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('fails closed on empty checkout_session_id', () {
      expect(
        () => PremiumCheckoutSessionModel.fromJson(
          validPayload()..['checkout_session_id'] = '',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('fails closed on malformed reused', () {
      expect(
        () => PremiumCheckoutSessionModel.fromJson(
          validPayload()..['reused'] = 'yes',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('fails closed on missing expires_at', () {
      final json = validPayload()..remove('expires_at');
      expect(
        () => PremiumCheckoutSessionModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SandboxBillingCheckoutUrl', () {
    test('accepts sandbox Pages checkout URL without explicit port', () {
      final result = SandboxBillingCheckoutUrl.validate(validCheckoutUrl);
      expect(result.isSuccess, isTrue);
      result.when(
        success: (uri) {
          expect(uri.scheme, 'https');
          expect(uri.host, SandboxBillingCheckoutUrl.expectedHost);
          expect(uri.hasPort, isFalse);
        },
        error: (_) => fail('expected success'),
      );
    });

    test('accepts explicit HTTPS default port 443', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev:443/billing/checkout'
        '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg',
      );
      expect(result.isSuccess, isTrue);
    });

    test('rejects http', () {
      final result = SandboxBillingCheckoutUrl.validate(
        validCheckoutUrl.replaceFirst('https', 'http'),
      );
      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('expected error'),
        error: (f) => expect(f, isA<AtlasCheckoutInvalidUrlFailure>()),
      );
    });

    test('rejects wrong host', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://evil.example/billing/checkout?_ptxn=txn_abc',
      );
      expect(result.isError, isTrue);
    });

    test('rejects evil host suffix', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev.evil.com/billing/checkout'
        '?_ptxn=txn_abc',
      );
      expect(result.isError, isTrue);
    });

    test('rejects wrong path', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/return?_ptxn=txn_abc',
      );
      expect(result.isError, isTrue);
    });

    test('rejects missing _ptxn', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/checkout',
      );
      expect(result.isError, isTrue);
    });

    test('rejects empty txn suffix', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/checkout?_ptxn=txn_',
      );
      expect(result.isError, isTrue);
    });

    test('rejects javascript URL', () {
      final result = SandboxBillingCheckoutUrl.validate('javascript:alert(1)');
      expect(result.isError, isTrue);
    });

    test('rejects non-default port 444', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev:444/billing/checkout'
        '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg',
      );
      expect(result.isError, isTrue);
    });

    test('rejects another non-default port', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev:8443/billing/checkout'
        '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg',
      );
      expect(result.isError, isTrue);
    });

    test('rejects username userInfo', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://user@project-atlas-bxh.pages.dev/billing/checkout'
        '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg',
      );
      expect(result.isError, isTrue);
    });

    test('rejects username/password userInfo', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://user:pass@project-atlas-bxh.pages.dev/billing/checkout'
        '?_ptxn=txn_01h8xckj7xqz9dkrgk1k3sy1jg',
      );
      expect(result.isError, isTrue);
    });

    test('rejects duplicate _ptxn', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/checkout'
        '?_ptxn=txn_one&_ptxn=txn_two',
      );
      expect(result.isError, isTrue);
    });

    test('rejects duplicate _ptxn when first valid and second invalid', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/checkout'
        '?_ptxn=txn_valid&_ptxn=txn_',
      );
      expect(result.isError, isTrue);
    });

    test('rejects duplicate _ptxn when both appear valid', () {
      final result = SandboxBillingCheckoutUrl.validate(
        'https://project-atlas-bxh.pages.dev/billing/checkout'
        '?_ptxn=txn_one&_ptxn=txn_two',
      );
      expect(result.isError, isTrue);
    });

    test('fragment does not bypass validation', () {
      final result = SandboxBillingCheckoutUrl.validate(
        '$validCheckoutUrl#/evil?_ptxn=txn_other',
      );
      expect(result.isSuccess, isTrue);
      result.when(
        success: (uri) {
          expect(uri.queryParametersAll['_ptxn'], [
            'txn_01h8xckj7xqz9dkrgk1k3sy1jg',
          ]);
        },
        error: (_) => fail('expected success'),
      );
    });
  });

  group('AtlasErrorCodes FunctionException + checkout mapper', () {
    test('extracts error_code from FunctionException details map', () {
      expect(
        AtlasErrorCodes.extract(
          const FunctionException(
            status: 403,
            details: {
              'schema_version': 1,
              'error_code': 'ATLAS_CHECKOUT_NOT_ELIGIBLE',
              'message': 'raw backend text must not surface',
              'retryable': false,
              'correlation_id': 'corr-1',
            },
          ),
        ),
        AtlasErrorCodes.checkoutNotEligible,
      );
    });

    for (final entry in <String, Type>{
      AtlasErrorCodes.checkoutUnavailable: AtlasCheckoutUnavailableFailure,
      AtlasErrorCodes.checkoutNotEligible: AtlasCheckoutNotEligibleFailure,
      AtlasErrorCodes.checkoutAlreadyOpen: AtlasCheckoutAlreadyOpenFailure,
      AtlasErrorCodes.checkoutInProgress: AtlasCheckoutInProgressFailure,
      AtlasErrorCodes.checkoutIdempotencyConflict:
          AtlasCheckoutIdempotencyConflictFailure,
      AtlasErrorCodes.providerOutcomeUnknown:
          AtlasProviderOutcomeUnknownFailure,
      AtlasErrorCodes.providerRequestRejected:
          AtlasProviderRequestRejectedFailure,
      AtlasErrorCodes.billingLinked: AtlasBillingLinkedFailure,
      AtlasErrorCodes.billingSyncPending: AtlasBillingSyncPendingFailure,
      AtlasErrorCodes.notCompanyOwner: AtlasNotCompanyOwnerFailure,
    }.entries) {
      test('maps ${entry.key}', () {
        final failure = SubscriptionErrorMapper.mapException(
          FunctionException(
            status: 400,
            details: {
              'error_code': entry.key,
              'message': 'RAW_SHOULD_NOT_APPEAR_$entry.key',
            },
          ),
          SubscriptionOperation.createPremiumCheckout,
        );
        expect(failure.runtimeType, entry.value);
        expect(failure.message, isNot(contains('RAW_SHOULD_NOT_APPEAR')));
      });
    }
  });

  group('SubscriptionRemoteDataSource.createCompanyPremiumCheckout', () {
    test(
      'invokes billing-checkout-create with body and Idempotency-Key',
      () async {
        String? calledName;
        Map<String, String>? calledHeaders;
        Object? calledBody;

        final ds = SubscriptionRemoteDataSource(
          // Client unused when invoker is injected.
          SupabaseClient('https://example.supabase.co', 'anon-key'),
          functionsInvoker: (name, {headers, body}) async {
            calledName = name;
            calledHeaders = headers;
            calledBody = body;
            return FunctionResponse(data: validPayload(), status: 200);
          },
        );

        final model = await ds.createCompanyPremiumCheckout(
          companyId: '11111111-1111-1111-1111-111111111111',
          idempotencyKey: 'idem-key-1',
        );

        expect(
          calledName,
          SubscriptionRemoteDataSource.checkoutCreateFunctionName,
        );
        expect(calledName, 'billing-checkout-create');
        expect(calledHeaders, {'Idempotency-Key': 'idem-key-1'});
        expect(calledBody, {
          'company_id': '11111111-1111-1111-1111-111111111111',
        });
        expect(model.checkoutUrl, validCheckoutUrl);
      },
    );

    test('malformed success data fails closed', () async {
      final ds = SubscriptionRemoteDataSource(
        SupabaseClient('https://example.supabase.co', 'anon-key'),
        functionsInvoker: (name, {headers, body}) async {
          return const FunctionResponse(data: 'not-a-map', status: 200);
        },
      );

      expect(
        () => ds.createCompanyPremiumCheckout(
          companyId: 'c1',
          idempotencyKey: 'k1',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SubscriptionRepositoryImpl.createCompanyPremiumCheckout', () {
    test('maps FunctionException error_code', () async {
      final repo = SubscriptionRepositoryImpl(
        SubscriptionRemoteDataSource(
          SupabaseClient('https://example.supabase.co', 'anon-key'),
          functionsInvoker: (name, {headers, body}) async {
            throw const FunctionException(
              status: 409,
              details: {
                'error_code': 'ATLAS_CHECKOUT_ALREADY_OPEN',
                'message': 'raw',
              },
            );
          },
        ),
      );

      final result = await repo.createCompanyPremiumCheckout(
        companyId: 'c1',
        idempotencyKey: 'k1',
      );
      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('expected error'),
        error: (f) => expect(f, isA<AtlasCheckoutAlreadyOpenFailure>()),
      );
    });

    test('parses success through repository', () async {
      final repo = SubscriptionRepositoryImpl(
        SubscriptionRemoteDataSource(
          SupabaseClient('https://example.supabase.co', 'anon-key'),
          functionsInvoker: (name, {headers, body}) async {
            return FunctionResponse(data: validPayload(), status: 200);
          },
        ),
      );

      final result = await repo.createCompanyPremiumCheckout(
        companyId: 'c1',
        idempotencyKey: 'k1',
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('CreateCompanyPremiumCheckout', () {
    test('empty companyId', () async {
      final result = await CreateCompanyPremiumCheckout(
        _CheckoutFakeRepo(),
      ).call(companyId: ' ', idempotencyKey: 'k1');
      expect(result.isError, isTrue);
    });

    test('forwards to repository', () async {
      final repo = _CheckoutFakeRepo(session: sampleSession());
      final result = await CreateCompanyPremiumCheckout(
        repo,
      ).call(companyId: 'c1', idempotencyKey: 'k-abc');
      expect(result.isSuccess, isTrue);
      expect(repo.createCalls, 1);
      expect(repo.lastIdempotencyKey, 'k-abc');
    });
  });

  group('CreatePremiumCheckoutController', () {
    test('one click invokes once; double tap while loading ignored', () async {
      final repo = _CheckoutFakeRepo(
        session: sampleSession(),
        delay: const Duration(milliseconds: 40),
      );
      final launcher = _FakeLauncher();
      var keySeq = 0;
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-${++keySeq}',
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        createPremiumCheckoutControllerProvider('c1').notifier,
      );
      final first = notifier.startCheckout();
      final second = notifier.startCheckout();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.createCalls, 1);
      expect(repo.lastIdempotencyKey, 'key-1');
      expect(launcher.launched, [Uri.parse(validCheckoutUrl)]);
      expect(keySeq, 1);
    });

    test('terminal error resets; later attempt gets new key', () async {
      final repo = _CheckoutFakeRepo(
        createFailure: const AtlasCheckoutUnavailableFailure(),
      );
      var keySeq = 0;
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(_FakeLauncher()),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-${++keySeq}',
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        createPremiumCheckoutControllerProvider('c1').notifier,
      );
      expect(await notifier.startCheckout(), isFalse);
      expect(repo.lastIdempotencyKey, 'key-1');
      expect(notifier.debugInFlightIdempotencyKey, isNull);

      repo.createFailure = null;
      repo.session = sampleSession();
      expect(await notifier.startCheckout(), isTrue);
      expect(repo.lastIdempotencyKey, 'key-2');
      expect(repo.createCalls, 2);
    });

    test('invalid URL blocked before launcher', () async {
      final repo = _CheckoutFakeRepo(
        session: sampleSession(
          checkoutUrl: 'https://evil.example/billing/checkout?_ptxn=txn_x',
        ),
      );
      final launcher = _FakeLauncher();
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(createPremiumCheckoutControllerProvider('c1').notifier)
          .startCheckout();
      expect(ok, isFalse);
      expect(launcher.launched, isEmpty);
      expect(
        container
            .read(createPremiumCheckoutControllerProvider('c1'))
            .errorMessage,
        const AtlasCheckoutInvalidUrlFailure().message,
      );
    });

    test('http URL blocked', () async {
      final repo = _CheckoutFakeRepo(
        session: sampleSession(
          checkoutUrl: validCheckoutUrl.replaceFirst('https', 'http'),
        ),
      );
      final launcher = _FakeLauncher();
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(createPremiumCheckoutControllerProvider('c1').notifier)
            .startCheckout(),
        isFalse,
      );
      expect(launcher.launched, isEmpty);
    });

    test('missing _ptxn blocked', () async {
      final repo = _CheckoutFakeRepo(
        session: sampleSession(
          checkoutUrl: 'https://project-atlas-bxh.pages.dev/billing/checkout',
        ),
      );
      final launcher = _FakeLauncher();
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(createPremiumCheckoutControllerProvider('c1').notifier)
            .startCheckout(),
        isFalse,
      );
      expect(launcher.launched, isEmpty);
    });

    test('launcher false → mapped failure', () async {
      final repo = _CheckoutFakeRepo(session: sampleSession());
      final launcher = _FakeLauncher(result: false);
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(createPremiumCheckoutControllerProvider('c1').notifier)
            .startCheckout(),
        isFalse,
      );
      expect(
        container
            .read(createPremiumCheckoutControllerProvider('c1'))
            .errorMessage,
        const AtlasCheckoutOpenFailure().message,
      );
    });

    test('launcher throw → mapped failure', () async {
      final repo = _CheckoutFakeRepo(session: sampleSession());
      final launcher = _FakeLauncher(throwOnLaunch: true);
      final container = ProviderContainer(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(launcher),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(createPremiumCheckoutControllerProvider('c1').notifier)
            .startCheckout(),
        isFalse,
      );
      expect(
        container
            .read(createPremiumCheckoutControllerProvider('c1'))
            .errorMessage,
        const AtlasCheckoutOpenFailure().message,
      );
    });
  });

  group('CompanyPlanCard checkout CTA', () {
    Future<void> pumpCard(
      WidgetTester tester,
      CompanySubscriptionOverview overview, {
      bool isWeb = true,
      List<Override> extraOverrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companySubscriptionOverviewProvider.overrideWith((ref, id) async {
              return overview;
            }),
            isBillingCheckoutWebPlatformProvider.overrideWithValue(isWeb),
            ...extraOverrides,
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

    testWidgets('web + eligible → purchase CTA visible', (tester) async {
      await pumpCard(tester, _checkoutEligibleFree());
      expect(find.text('Passa a Premium'), findsOneWidget);
      expect(find.text('Attiva la prova Premium'), findsNothing);
    });

    testWidgets('checkout-ineligible → purchase CTA absent', (tester) async {
      await pumpCard(tester, _checkoutEligibleFree(isCheckoutEligible: false));
      expect(find.text('Passa a Premium'), findsNothing);
      expect(
        find.text('La gestione del piano sarà disponibile prossimamente.'),
        findsOneWidget,
      );
    });

    testWidgets('trial eligible wins; purchase CTA absent', (tester) async {
      await pumpCard(
        tester,
        _checkoutEligibleFree(canActivateTrial: true, isCheckoutEligible: true),
      );
      expect(find.text('Attiva la prova Premium'), findsOneWidget);
      expect(find.text('Passa a Premium'), findsNothing);
    });

    testWidgets('non-web → purchase CTA absent', (tester) async {
      await pumpCard(tester, _checkoutEligibleFree(), isWeb: false);
      expect(find.text('Passa a Premium'), findsNothing);
    });

    testWidgets('loading disables CTA', (tester) async {
      final repo = _CheckoutFakeRepo(
        session: sampleSession(),
        delay: const Duration(milliseconds: 200),
      );
      await pumpCard(
        tester,
        _checkoutEligibleFree(),
        extraOverrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          billingCheckoutUrlLauncherProvider.overrideWithValue(_FakeLauncher()),
          billingCheckoutIdempotencyKeyGeneratorProvider.overrideWithValue(
            () => 'key-1',
          ),
        ],
      );

      await tester.tap(find.text('Passa a Premium'));
      await tester.pump();
      expect(find.text('Preparazione del checkout...'), findsOneWidget);
      final loadingButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(loadingButton.onPressed, isNull);
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
    });
  });
}

CompanySubscriptionOverview _checkoutEligibleFree({
  bool canActivateTrial = false,
  bool isCheckoutEligible = true,
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
    documentsUsed: 0,
    isUnlimited: false,
    canActivateTrial: canActivateTrial,
    isCheckoutEligible: isCheckoutEligible,
  );
}

class _FakeLauncher implements BillingCheckoutUrlLauncher {
  _FakeLauncher({this.result = true, this.throwOnLaunch = false});

  final bool result;
  final bool throwOnLaunch;
  final List<Uri> launched = [];

  @override
  Future<bool> launch(Uri uri) async {
    if (throwOnLaunch) {
      throw Exception('launch failed');
    }
    launched.add(uri);
    return result;
  }
}

class _CheckoutFakeRepo implements SubscriptionRepository {
  _CheckoutFakeRepo({
    this.session,
    this.createFailure,
    this.delay = Duration.zero,
  });

  PremiumCheckoutSession? session;
  Failure? createFailure;
  final Duration delay;
  int createCalls = 0;
  String? lastIdempotencyKey;
  String? lastCompanyId;

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

  @override
  Future<Result<PremiumCheckoutSession>> createCompanyPremiumCheckout({
    required String companyId,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    lastCompanyId = companyId;
    lastIdempotencyKey = idempotencyKey;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (createFailure != null) {
      return Error(createFailure!);
    }
    return Success(session!);
  }
}
