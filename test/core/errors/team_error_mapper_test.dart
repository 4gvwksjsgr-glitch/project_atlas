import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/errors/team_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('TeamErrorMapper', () {
    test('mappa ATLAS_INVITE_ALREADY_PENDING su ValidationFailure', () {
      final failure = TeamErrorMapper.mapException(
        const PostgrestException(
          message: 'ATLAS_INVITE_ALREADY_PENDING',
          code: 'P0001',
        ),
        TeamOperation.createInvite,
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        'Esiste già un invito in sospeso per questa email.',
      );
    });

    test('mappa ATLAS_INSUFFICIENT_PRIVILEGES su AuthFailure', () {
      final failure = TeamErrorMapper.mapException(
        const PostgrestException(
          message: 'ATLAS_INSUFFICIENT_PRIVILEGES',
          code: 'P0001',
        ),
        TeamOperation.listInvites,
      );

      expect(failure, isA<AuthFailure>());
      expect(
        failure.message,
        'Non hai i permessi per gestire i membri di questa azienda.',
      );
    });

    test('mappa trigger last owner su ValidationFailure', () {
      final failure = TeamErrorMapper.mapException(
        const PostgrestException(
          message: 'Cannot demote the last owner',
          code: 'P0001',
        ),
        TeamOperation.changeMemberRole,
      );

      expect(failure, isA<ValidationFailure>());
      expect(
        failure.message,
        'Non puoi rimuovere o declassare l\'ultimo proprietario.',
      );
    });
  });
}
