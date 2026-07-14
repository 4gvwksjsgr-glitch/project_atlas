import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260714000002_grant_private_rls_helpers.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260714000002_grant_private_rls_helpers.sql',
      ).readAsStringSync();
    });

    test('concede EXECUTE a authenticated con firme corrette', () {
      expect(
        migrationSql,
        contains(
          'GRANT EXECUTE ON FUNCTION private.is_company_member(UUID, UUID)',
        ),
      );
      expect(
        migrationSql,
        contains(
          'GRANT EXECUTE ON FUNCTION private.has_company_role(UUID, public.company_role[], UUID)',
        ),
      );
      expect(migrationSql, contains('TO authenticated'));
    });

    test('non concede permessi a anon', () {
      expect(migrationSql.toLowerCase(), isNot(contains('to anon')));
    });
  });
}
