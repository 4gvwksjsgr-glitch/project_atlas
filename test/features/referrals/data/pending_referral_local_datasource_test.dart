import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/features/referrals/data/datasource/pending_referral_local_datasource.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';

void main() {
  group('PendingReferralLocalDataSource', () {
    setUp(() async {
      await setUpMockSharedPreferences();
    });

    test('set/get/clear pending code', () async {
      final ds = PendingReferralLocalDataSource(appSharedPreferences!);

      expect(ds.getPendingCode(), isNull);

      await ds.setPendingCode('  CodeABCDEF123456  ');
      expect(ds.getPendingCode(), 'CodeABCDEF123456');
      expect(
        appSharedPreferences!.getString(
          PendingReferralLocalDataSource.storageKey,
        ),
        'CodeABCDEF123456',
      );

      await ds.clearPendingCode();
      expect(ds.getPendingCode(), isNull);
      expect(
        appSharedPreferences!.containsKey(
          PendingReferralLocalDataSource.storageKey,
        ),
        isFalse,
      );
    });

    test('set empty clears', () async {
      final ds = PendingReferralLocalDataSource(appSharedPreferences!);
      await ds.setPendingCode('KeepMeABCDEF1234');
      await ds.setPendingCode('   ');
      expect(ds.getPendingCode(), isNull);
    });
  });
}
