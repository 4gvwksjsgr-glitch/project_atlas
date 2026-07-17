import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260718000002_harden_transactions_privileges.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260718000002_harden_transactions_privileges.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('revoca ALL da anon e authenticated', () {
      expect(
        migrationSql,
        contains('REVOKE ALL ON TABLE public.transactions FROM anon'),
      );
      expect(
        migrationSql,
        contains('REVOKE ALL ON TABLE public.transactions FROM authenticated'),
      );
    });

    test('grant finale esclusivamente SELECT, INSERT, UPDATE', () {
      expect(migrationSql, contains('GRANT SELECT, INSERT, UPDATE'));
      expect(migrationSql, contains('ON TABLE public.transactions'));
      expect(migrationSql, contains('TO authenticated'));
      expect(migrationSql, isNot(contains('GRANT DELETE')));
      expect(migrationSql, isNot(contains('GRANT ALL')));
      expect(migrationSql, isNot(contains('GRANT TRUNCATE')));
      expect(migrationSql, isNot(contains('GRANT REFERENCES')));
      expect(migrationSql, isNot(contains('GRANT TRIGGER')));
      expect(migrationSql, isNot(contains('GRANT MAINTAIN')));
    });

    test('non tocca altre tabelle né privilegi globali', () {
      expect(migrationSql, isNot(contains('ALTER DEFAULT PRIVILEGES')));
      expect(migrationSql, isNot(contains('public.companies')));
      expect(migrationSql, isNot(contains('service_role')));
    });
  });
}
