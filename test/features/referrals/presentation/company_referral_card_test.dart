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
        repository: _NoEnsureRepo(),
      );

      expect(find.text('1 di 5 mesi Premium'), findsOneWidget);
      expect(find.text('1 mesi Premium guadagnati'), findsOneWidget);
      expect(find.text('Il tuo link di invito'), findsNothing);
      expect(find.text('Copia link'), findsNothing);
      expect(find.text('Cronologia'), findsNothing);
      expect(find.textContaining('Amico iscritto'), findsNothing);
    });
  });
}

class _NoEnsureRepo implements ReferralRepository {
  @override
  Future<Result<ClaimReferralResult>> claimReferral({required String code}) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ReferralLink>> getOrCreateCompanyReferralLink({
    required String companyId,
  }) async {
    fail('non-owner non deve chiamare get_or_create');
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
}
