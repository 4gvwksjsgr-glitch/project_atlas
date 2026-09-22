import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/referral_error_mapper.dart';

void main() {
  group('ReferralErrorMapper.isTerminalClaimFailure', () {
    test('clears on invalid / window closed / self denied', () {
      expect(
        ReferralErrorMapper.isTerminalClaimFailure(
          const ValidationFailure('Il codice referral non è valido.'),
        ),
        isTrue,
      );
      expect(
        ReferralErrorMapper.isTerminalClaimFailure(
          const ValidationFailure(
            'Non è più possibile reclamare un codice referral.',
          ),
        ),
        isTrue,
      );
      expect(
        ReferralErrorMapper.isTerminalClaimFailure(
          const ValidationFailure(
            'Non puoi usare il codice referral della tua azienda.',
          ),
        ),
        isTrue,
      );
    });

    test('keeps pending on network/unknown', () {
      expect(
        ReferralErrorMapper.isTerminalClaimFailure(const NetworkFailure()),
        isFalse,
      );
      expect(
        ReferralErrorMapper.isTerminalClaimFailure(const UnknownFailure()),
        isFalse,
      );
    });
  });
}
