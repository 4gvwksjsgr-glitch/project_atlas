import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_state.dart';
import 'package:project_atlas/features/subscription/domain/entities/company_subscription_overview.dart';
import 'package:project_atlas/features/subscription/domain/entities/premium_checkout_session.dart';
import 'package:project_atlas/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:project_atlas/features/subscription/presentation/controllers/checkout_return_refresh_controller.dart';
import 'package:project_atlas/features/subscription/presentation/providers/subscription_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ActiveCompanyContext company(String id) => ActiveCompanyContext(
    companyId: id,
    companyName: 'Co $id',
    companySlug: 'co-$id',
    role: CompanyRole.owner,
    membershipId: 'm-$id',
  );

  CompanySubscriptionOverview freeOverview(String companyId) {
    return CompanySubscriptionOverview(
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
      documentsUsed: 0,
      isUnlimited: false,
    );
  }

  CompanySubscriptionOverview premiumOverview(String companyId) {
    return CompanySubscriptionOverview(
      companyId: companyId,
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
      documentsUsed: 0,
      isUnlimited: true,
      entitlementOrigin: EntitlementOrigin.provider,
      providerAccessStatus: ProviderAccessStatus.entitled,
    );
  }

  List<Override> baseOverrides({
    required SubscriptionRepository repo,
    required ActiveCompanyController active,
  }) {
    return [
      subscriptionRepositoryProvider.overrideWithValue(repo),
      activeCompanyControllerProvider.overrideWith(() => active),
      checkoutReturnRefreshAttachLifecycleProvider.overrideWithValue(false),
    ];
  }

  Future<void> settleAndClear(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final notifier = container.read(
      checkoutReturnRefreshControllerProvider.notifier,
    );
    notifier.clearPending();
    await tester.pump(const Duration(seconds: 10));
  }

  group('CheckoutReturnRefreshController', () {
    testWidgets('A. no checkout pending → resume does not refresh', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      container.read(checkoutReturnRefreshControllerProvider);
      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );

      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await settleAndClear(tester, container);

      expect(repo.overviewCalls, isEmpty);
      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );
    });

    testWidgets('B. checkout launched → pending refresh recorded', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: _OverviewFakeRepo(overviewFor: freeOverview),
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');

      final state = container.read(checkoutReturnRefreshControllerProvider);
      expect(state.isPending, isTrue);
      expect(state.pendingCompanyId, 'c1');
      expect(state.attemptsCompleted, 0);
      await settleAndClear(tester, container);
    });

    testWidgets('C. return/focus → overview refreshed immediately', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(repo.overviewCalls, isNotEmpty);
      expect(repo.overviewCalls.first, 'c1');
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        1,
      );
      await settleAndClear(tester, container);
    });

    testWidgets('D. backend already Premium → stops immediately', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: premiumOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(seconds: 6));

      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        1,
      );
      expect(repo.overviewCalls, isNotEmpty);
      expect(repo.overviewCalls.first, 'c1');
      // No further attempts after Premium.
      expect(repo.overviewCalls.length, lessThanOrEqualTo(2));
      await settleAndClear(tester, container);
    });

    testWidgets('E. still Free → bounded retry ~2s, max 3 attempts', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);

      await tester.pump();
      await tester.pump(Duration.zero);
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        1,
      );
      final afterFirst = repo.overviewCalls.length;
      expect(afterFirst, greaterThanOrEqualTo(1));

      await tester.pump(const Duration(seconds: 2));
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        2,
      );
      expect(repo.overviewCalls.length, greaterThan(afterFirst));
      final afterSecond = repo.overviewCalls.length;

      await tester.pump(const Duration(seconds: 2));
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        3,
      );
      expect(repo.overviewCalls.length, greaterThan(afterSecond));

      await tester.pump(const Duration(seconds: 4));
      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        3,
      );
      await settleAndClear(tester, container);
    });

    testWidgets('F. tenant safety — company A pending does not refresh B', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final active = _FixedActiveCompany(company('c1'));
      final container = ProviderContainer(
        overrides: baseOverrides(repo: repo, active: active),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');

      active.setContext(company('c2'));
      await tester.pump();

      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );

      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(repo.overviewCalls, isEmpty);
      await settleAndClear(tester, container);
    });

    testWidgets('G. lifecycle cleanup + no duplicate concurrent loops', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(
        overviewFor: freeOverview,
        delay: const Duration(milliseconds: 50),
      );
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(
            repo: repo,
            active: _FixedActiveCompany(company('c1')),
          ),
          // Keep lifecycle attached for this cleanup assertion.
          checkoutReturnRefreshAttachLifecycleProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      expect(notifier.debugHasLifecycleListener, isTrue);

      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();

      expect(notifier.debugRunInFlight, isTrue);
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        lessThanOrEqualTo(1),
      );
      // Second resume must not start another bounded run while one is in flight.
      expect(notifier.debugRunInFlight, isTrue);

      await settleAndClear(tester, container);
      expect(notifier.debugRunInFlight, isFalse);
      expect(notifier.debugHasActiveTimer, isFalse);

      container.dispose();
      expect(notifier.debugHasLifecycleListener, isFalse);
      expect(notifier.debugHasActiveTimer, isFalse);
    });

    testWidgets('H. authority — overview remains sole entitlement source', (
      tester,
    ) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(seconds: 6));

      final overview = await container.read(
        companySubscriptionOverviewProvider('c1').future,
      );
      expect(overview.isEffectivePremium, isFalse);
      expect(overview.effectivePlanCode, 'free');
      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );
      await settleAndClear(tester, container);
    });

    testWidgets('Premium mid-retry stops further attempts', (tester) async {
      final repo = _OverviewFakeRepo(overviewFor: freeOverview);
      final container = ProviderContainer(
        overrides: baseOverrides(
          repo: repo,
          active: _FixedActiveCompany(company('c1')),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        checkoutReturnRefreshControllerProvider.notifier,
      );
      notifier.markPending('c1');
      notifier.debugHandleLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(repo.overviewCalls.length, greaterThanOrEqualTo(1));

      repo.overviewFor = premiumOverview;
      await tester.pump(const Duration(seconds: 2));
      expect(
        container
            .read(checkoutReturnRefreshControllerProvider)
            .attemptsCompleted,
        greaterThanOrEqualTo(2),
      );
      final callsAfterPremium = repo.overviewCalls.length;

      await tester.pump(const Duration(seconds: 4));
      expect(repo.overviewCalls.length, callsAfterPremium);
      expect(
        container.read(checkoutReturnRefreshControllerProvider).isPending,
        isFalse,
      );
      await settleAndClear(tester, container);
    });
  });
}

class _FixedActiveCompany extends ActiveCompanyController {
  _FixedActiveCompany(this._context);

  ActiveCompanyContext? _context;

  void setContext(ActiveCompanyContext? context) {
    _context = context;
    state = ActiveCompanyState(context: _context, resolved: true);
  }

  @override
  ActiveCompanyState build() {
    return ActiveCompanyState(context: _context, resolved: true);
  }
}

class _OverviewFakeRepo implements SubscriptionRepository {
  _OverviewFakeRepo({required this.overviewFor, this.delay = Duration.zero});

  CompanySubscriptionOverview Function(String companyId) overviewFor;
  final Duration delay;
  final List<String> overviewCalls = [];

  @override
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  }) async {
    overviewCalls.add(companyId);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return Success(overviewFor(companyId));
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
    return const Error(AtlasCheckoutUnavailableFailure());
  }
}
