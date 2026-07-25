import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260724000002_harden_transaction_categories_privileges.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260724000002_harden_transaction_categories_privileges.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('revoca ALL da PUBLIC, anon e authenticated (tabella e colonne)', () {
      expect(
        migrationSql,
        contains(
          'REVOKE ALL ON TABLE public.transaction_categories FROM PUBLIC',
        ),
      );
      expect(
        migrationSql,
        contains('REVOKE ALL ON TABLE public.transaction_categories FROM anon'),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL ON TABLE public.transaction_categories FROM authenticated',
        ),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL (\n'
          '  id,\n'
          '  company_id,\n'
          '  name,\n'
          '  kind,\n'
          '  is_active,\n'
          '  created_at,\n'
          '  updated_at\n'
          ') ON TABLE public.transaction_categories FROM PUBLIC;',
        ),
      );
      expect(
        migrationSql,
        contains(') ON TABLE public.transaction_categories FROM anon;'),
      );
      expect(
        migrationSql,
        contains(
          ') ON TABLE public.transaction_categories FROM authenticated;',
        ),
      );
    });

    test('grant finale SELECT tabella; INSERT/UPDATE solo colonne consentite', () {
      expect(
        migrationSql,
        contains(
          'GRANT SELECT\n'
          'ON TABLE public.transaction_categories\n'
          'TO authenticated;',
        ),
      );
      expect(migrationSql, isNot(contains('GRANT SELECT, INSERT')));

      final insertGrantMatch = RegExp(
        r'GRANT INSERT\s*\(([\s\S]*?)\)\s*ON TABLE public\.transaction_categories',
      ).firstMatch(migrationSql);
      expect(insertGrantMatch, isNotNull);
      final insertColumns = insertGrantMatch!
          .group(1)!
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      expect(
        insertColumns,
        unorderedEquals(['company_id', 'name', 'kind', 'is_active']),
      );
      expect(insertColumns, isNot(contains('id')));
      expect(insertColumns, isNot(contains('created_at')));
      expect(insertColumns, isNot(contains('updated_at')));

      final updateGrantMatch = RegExp(
        r'GRANT UPDATE\s*\(([\s\S]*?)\)\s*ON TABLE public\.transaction_categories',
      ).firstMatch(migrationSql);
      expect(updateGrantMatch, isNotNull);
      final updateColumns = updateGrantMatch!
          .group(1)!
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      expect(updateColumns, unorderedEquals(['name', 'is_active']));
      expect(updateColumns, isNot(contains('company_id')));
      expect(updateColumns, isNot(contains('kind')));
      expect(updateColumns, isNot(contains('created_at')));
      expect(updateColumns, isNot(contains('updated_at')));
      expect(updateColumns, isNot(contains('id')));

      expect(migrationSql, isNot(contains('GRANT DELETE')));
      expect(migrationSql, isNot(contains('GRANT ALL')));
      expect(migrationSql, isNot(contains('GRANT TRUNCATE')));
    });

    test('non tocca altre tabelle né privilegi globali né service_role', () {
      expect(migrationSql, isNot(contains('ALTER DEFAULT PRIVILEGES')));
      expect(migrationSql, isNot(contains('public.transactions')));
      expect(migrationSql, isNot(contains('public.clients')));
      expect(migrationSql, isNot(contains('service_role')));
    });
  });
}
