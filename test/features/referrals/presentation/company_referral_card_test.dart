import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/referrals/domain/entities/referral_link.dart';
import 'package:project_atlas/features/referrals/domain/entities/referral_overview.dart';
import 'package:project_atlas/features/referrals/domain/repositories/referral_repository.dart';
import 'package:project_atlas/features/referrals/presentation/providers/referral_providers.dart';
import 'package:project_atlas/features/referrals/presentation/widgets/company_referral_card.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

void main() {
  group('CompanyReferralCard', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required ReferralOverview overview,
      ReferralRepository? repository,
    }) async {
      // Fresh ProviderScope per pump: overrideWith closures are not rebound.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            referralOverviewProvider.overrideWith((ref, id) async => overview),
            referralAppBaseUrlProvider.overrideWithValue('https://app.test'),
            if (repository != null)
              referralRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('it'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CompanyReferralCard(companyId: 'c1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ReferralOverview ownerOverview({
      int rewardedCount = 1,
      int pending = 0,
      int applying = 0,
      int redeemed = 0,
      String? blockReason,
      String? openStatus,
      bool isOwner = true,
    }) {
      return ReferralOverview(
        companyId: 'c1',
        code: isOwner ? 'OwnerCodeABCDEF1234' : null,
        rewardedCount: rewardedCount,
        maxRewards: 5,
        pendingRedemptionMonths: pending,
        applyingRedemptionMonths: applying,
        redeemedRedemptionMonths: redeemed,
        redemptionBlockReason: blockReason,
        openOperationStatus: openStatus,
        isOwner: isOwner,
        items: const [],
      );
    }

    testWidgets('owner vede link, conteggio e cronologia', (tester) async {
      await pumpCard(
        tester,
        overview: ReferralOverview(
          companyId: 'c1',
          code: 'OwnerCodeABCDEF1234',
          rewardedCount: 2,
          maxRewards: 5,
          pendingRedemptionMonths: 2,
          isOwner: true,
          items: [
            ReferralHistoryItem(
              referralId: 'r1',
              status: ReferralItemStatus.rewarded,
              claimedAt: DateTime.utc(2026, 9, 1),
              qualifiedAt: DateTime.utc(2026, 9, 2),
              label: 'friend',
            ),
          ],
        ),
      );

      expect(find.text('Invita un amico'), findsOneWidget);
      expect(find.text('2 di 5 mesi Premium'), findsOneWidget);
      expect(find.text('2 mesi Premium guadagnati'), findsOneWidget);
      expect(find.text('pagamento annullato'), findsNothing);
      expect(
        find.text('https://app.test/ref/OwnerCodeABCDEF1234'),
        findsOneWidget,
      );
      expect(find.text('Copia link'), findsOneWidget);
      expect(find.text('Rigenera link'), findsOneWidget);
      expect(find.text('Cronologia'), findsOneWidget);
      expect(find.textContaining('Amico iscritto'), findsOneWidget);
    });

    testWidgets('non-owner vede solo i conteggi', (tester) async {
      await pumpCard(
        tester,
        overview: const ReferralOverview(
          companyId: 'c1',
          code: null,
          rewardedCount: 1,
          maxRewards: 5,
          pendingRedemptionMonths: 1,
          isOwner: false,
          items: [],
        ),
        repository: _FakeReferralRepo(),
      );

      expect(find.text('1 di 5 mesi Premium'), findsOneWidget);
      expect(find.text('1 mese Premium guadagnato'), findsOneWidget);
      expect(find.text('Il tuo link di invito'), findsNothing);
      expect(find.text('Copia link'), findsNothing);
      expect(find.text('Cronologia'), findsNothing);
      expect(find.textContaining('Amico iscritto'), findsNothing);
    });

    group('stato riscatto premio (owner)', () {
      testWidgets('pending: mesi disponibili plurale e singolare', (
        tester,
      ) async {
        await pumpCard(tester, overview: ownerOverview(pending: 3));
        expect(find.text('3 mesi Premium disponibili'), findsOneWidget);

        await pumpCard(tester, overview: ownerOverview(pending: 1));
        expect(find.text('1 mese Premium disponibile'), findsOneWidget);
        expect(find.textContaining('annullato'), findsNothing);
      });

      testWidgets('applying: applicazione in corso senza promettere pagamenti', (
        tester,
      ) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            rewardedCount: 2,
            applying: 2,
            openStatus: 'provider_accepted',
          ),
        );

        expect(find.text('Applicazione del premio in corso'), findsOneWidget);
        expect(find.text('2 di 5 mesi Premium'), findsOneWidget);
        expect(find.textContaining('annullato'), findsNothing);
        expect(find.text('Riprova'), findsNothing);
      });

      testWidgets('redeemed: premio applicato con conteggio', (tester) async {
        await pumpCard(
          tester,
          overview: ownerOverview(rewardedCount: 3, redeemed: 3),
        );

        expect(find.text('Premio applicato: 3 mesi Premium'), findsOneWidget);
        expect(find.text('3 mesi Premium guadagnati'), findsOneWidget);
        expect(find.text('Applicazione del premio in corso'), findsNothing);

        await pumpCard(
          tester,
          overview: ownerOverview(rewardedCount: 1, redeemed: 1),
        );
        expect(find.text('Premio applicato: 1 mese Premium'), findsOneWidget);
      });

      testWidgets('X/5 resta corretto con stati misti', (tester) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            rewardedCount: 5,
            pending: 1,
            applying: 2,
            redeemed: 2,
            openStatus: 'claimed',
          ),
        );

        expect(find.text('5 di 5 mesi Premium'), findsOneWidget);
        expect(find.text('5 mesi Premium guadagnati'), findsOneWidget);
        expect(find.text('Premio applicato: 2 mesi Premium'), findsOneWidget);
        expect(find.text('Applicazione del premio in corso'), findsOneWidget);
        expect(find.text('1 mese Premium disponibile'), findsOneWidget);
      });

      testWidgets('bloccato free/unlinked: attesa Premium attivo', (
        tester,
      ) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 1,
            blockReason: 'ATLAS_REFERRAL_PROVIDER_UNLINKED',
          ),
        );

        expect(
          find.text(
            "Il premio verrà applicato quando l'abbonamento Premium sarà attivo",
          ),
          findsOneWidget,
        );
        expect(find.text('Riprova'), findsNothing);
        expect(find.textContaining('ATLAS_'), findsNothing);
      });

      testWidgets('bloccato trial: attesa Premium attivo', (tester) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 2,
            blockReason: 'ATLAS_REFERRAL_PROVIDER_TRIALING',
          ),
        );

        expect(
          find.text(
            'Il premio verrà applicato al termine della prova, '
            "quando l'abbonamento Premium sarà attivo",
          ),
          findsOneWidget,
        );
        expect(find.text('Riprova'), findsNothing);
      });

      testWidgets('bloccato past_due: attesa regolarizzazione', (tester) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 1,
            blockReason: 'ATLAS_REFERRAL_PROVIDER_PAST_DUE',
          ),
        );

        expect(
          find.text(
            "Il premio è in attesa della regolarizzazione dell'abbonamento",
          ),
          findsOneWidget,
        );
        expect(find.text('Riprova'), findsNothing);
      });

      testWidgets('bloccato scheduled cancel / canceled senza pagamento annullato', (
        tester,
      ) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 1,
            blockReason: 'ATLAS_REFERRAL_SCHEDULED_CANCEL',
          ),
        );
        expect(
          find.text(
            "Il premio è in attesa: l'abbonamento Premium non risulta in rinnovo",
          ),
          findsOneWidget,
        );
        expect(find.textContaining('pagamento'), findsNothing);

        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 1,
            blockReason: 'ATLAS_REFERRAL_PROVIDER_CANCELED',
          ),
        );
        expect(
          find.text(
            "Il premio non è stato applicato perché l'abbonamento Premium "
            'non è attivo',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('pagamento'), findsNothing);
      });

      testWidgets('owner vede Riprova per retryable_failed e needs_reconcile', (
        tester,
      ) async {
        final repo = _FakeReferralRepo();
        await pumpCard(
          tester,
          overview: ownerOverview(
            applying: 1,
            openStatus: 'retryable_failed',
            blockReason: 'ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN',
          ),
          repository: repo,
        );

        expect(
          find.text('Applicazione del premio non completata. Puoi riprovare.'),
          findsOneWidget,
        );
        expect(find.textContaining('ATLAS_'), findsNothing);
        expect(find.text('Riprova'), findsOneWidget);

        await tester.tap(find.text('Riprova'));
        await tester.pumpAndSettle();
        expect(repo.retryCalls, ['c1']);

        await pumpCard(
          tester,
          overview: ownerOverview(applying: 1, openStatus: 'needs_reconcile'),
          repository: repo,
        );
        expect(find.text('Applicazione del premio in corso'), findsOneWidget);
        expect(find.text('Riprova'), findsOneWidget);
      });

      testWidgets('owner vede Riprova per blocco transitorio', (tester) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            pending: 1,
            blockReason: 'ATLAS_REFERRAL_NEAR_RENEWAL',
          ),
          repository: _FakeReferralRepo(),
        );

        expect(
          find.text('Il premio verrà applicato dopo il prossimo rinnovo'),
          findsOneWidget,
        );
        expect(find.text('Riprova'), findsOneWidget);
      });

      testWidgets('non-owner non vede stato riscatto né Riprova', (
        tester,
      ) async {
        await pumpCard(
          tester,
          overview: ownerOverview(
            isOwner: false,
            pending: 1,
            applying: 1,
            openStatus: 'retryable_failed',
            blockReason: 'ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN',
          ),
          repository: _FakeReferralRepo(),
        );

        expect(find.text('Riprova'), findsNothing);
        expect(find.text('1 mese Premium disponibile'), findsNothing);
        expect(find.text('Applicazione del premio in corso'), findsNothing);
        expect(
          find.text('Applicazione del premio non completata. Puoi riprovare.'),
          findsNothing,
        );
        expect(find.text('2 mesi Premium guadagnati'), findsOneWidget);
      });
    });

    testWidgets('cambio azienda: stato riscatto isolato per companyId', (
      tester,
    ) async {
      final overviews = {
        'c1': const ReferralOverview(
          companyId: 'c1',
          code: 'CodeCompanyOne12345',
          rewardedCount: 2,
          maxRewards: 5,
          pendingRedemptionMonths: 2,
          redemptionBlockReason: 'ATLAS_REFERRAL_PROVIDER_PAST_DUE',
          isOwner: true,
          items: [],
        ),
        'c2': const ReferralOverview(
          companyId: 'c2',
          code: 'CodeCompanyTwo12345',
          rewardedCount: 4,
          maxRewards: 5,
          pendingRedemptionMonths: 0,
          redeemedRedemptionMonths: 4,
          isOwner: true,
          items: [],
        ),
      };

      Widget buildFor(String companyId) {
        return ProviderScope(
          overrides: [
            referralOverviewProvider.overrideWith(
              (ref, id) async => overviews[id]!,
            ),
            referralAppBaseUrlProvider.overrideWithValue('https://app.test'),
            referralRepositoryProvider.overrideWithValue(_FakeReferralRepo()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('it'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CompanyReferralCard(
                  key: ValueKey(companyId),
                  companyId: companyId,
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildFor('c1'));
      await tester.pumpAndSettle();
      expect(find.text('2 di 5 mesi Premium'), findsOneWidget);
      expect(
        find.text(
          "Il premio è in attesa della regolarizzazione dell'abbonamento",
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(buildFor('c2'));
      await tester.pumpAndSettle();
      expect(find.text('4 di 5 mesi Premium'), findsOneWidget);
      expect(find.text('Premio applicato: 4 mesi Premium'), findsOneWidget);
      expect(find.text('2 di 5 mesi Premium'), findsNothing);
      expect(
        find.text(
          "Il premio è in attesa della regolarizzazione dell'abbonamento",
        ),
        findsNothing,
      );
      expect(find.textContaining('CodeCompanyOne'), findsNothing);
    });
  });
}

class _FakeReferralRepo implements ReferralRepository {
  final retryCalls = <String>[];

  @override
  Future<Result<ClaimReferralResult>> claimReferral({required String code}) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ReferralLink>> getOrCreateCompanyReferralLink({
    required String companyId,
  }) async {
    fail('get_or_create non deve essere chiamato');
  }

  @override
  Future<Result<ReferralOverview>> getReferralOverview({
    required String companyId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ReferralLink>> regenerateCompanyReferralLink({
    required String companyId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<RetryReferralRedemptionResult>> retryReferralRedemption({
    required String companyId,
  }) async {
    retryCalls.add(companyId);
    return const Success(
      RetryReferralRedemptionResult(
        outcome: 'existing_open',
        operationStatus: 'retryable_failed',
        pendingMonths: 0,
        applyingMonths: 1,
        redeemedMonths: 0,
      ),
    );
  }
}
