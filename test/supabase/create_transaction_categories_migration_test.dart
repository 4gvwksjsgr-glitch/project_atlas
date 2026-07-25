import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260724000001_create_transaction_categories.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260724000001_create_transaction_categories.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('crea tabella con colonne, check e unique richiesti', () {
      expect(
        migrationSql,
        contains('CREATE TABLE public.transaction_categories'),
      );
      expect(migrationSql, contains('company_id'));
      expect(migrationSql, contains('kind        public.transaction_kind'));
      expect(
        migrationSql,
        contains('is_active   BOOLEAN NOT NULL DEFAULT TRUE'),
      );
      expect(
        migrationSql,
        contains('REFERENCES public.companies(id) ON DELETE CASCADE'),
      );
      expect(migrationSql, contains('transaction_categories_name_not_empty'));
      expect(migrationSql, contains('transaction_categories_name_trimmed'));
      expect(migrationSql, contains('transaction_categories_name_max_len'));
      expect(
        migrationSql,
        contains('transaction_categories_company_id_id_kind_unique'),
      );
      expect(migrationSql, contains('UNIQUE (company_id, id, kind)'));
      expect(
        migrationSql,
        contains('transaction_categories_company_kind_lower_name_unique'),
      );
      expect(migrationSql, contains('(company_id, kind, lower(name))'));
      expect(
        migrationSql,
        contains('idx_transaction_categories_company_kind_active'),
      );
      expect(
        migrationSql,
        isNot(contains('idx_transaction_categories_company_id')),
      );
      expect(
        migrationSql,
        contains('EXECUTE FUNCTION public.set_updated_at()'),
      );
      expect(migrationSql, isNot(contains('ALTER TABLE public.transactions')));
    });

    test('immutabilità company_id e kind via trigger', () {
      expect(
        migrationSql,
        contains(
          'CREATE FUNCTION private.enforce_transaction_categories_immutable_keys()',
        ),
      );
      expect(
        migrationSql,
        isNot(
          contains(
            'CREATE OR REPLACE FUNCTION private.enforce_transaction_categories_immutable_keys()',
          ),
        ),
      );
      expect(migrationSql, contains('company_id cannot be changed'));
      expect(migrationSql, contains('kind cannot be changed'));
      expect(
        migrationSql,
        contains('trg_transaction_categories_immutable_keys'),
      );
    });

    test('FORCE RLS SELECT/INSERT/UPDATE senza DELETE', () {
      expect(migrationSql, contains('ENABLE ROW LEVEL SECURITY'));
      expect(migrationSql, contains('FORCE ROW LEVEL SECURITY'));
      expect(migrationSql, contains('transaction_categories_select_member'));
      expect(
        migrationSql,
        contains('transaction_categories_insert_owner_admin_manager'),
      );
      expect(
        migrationSql,
        contains('transaction_categories_update_owner_admin_manager'),
      );
      expect(migrationSql, isNot(contains('FOR DELETE')));
      expect(
        migrationSql,
        contains(
          'REVOKE DELETE ON public.transaction_categories FROM authenticated',
        ),
      );
    });

    test('privilegi: SELECT tabella; INSERT/UPDATE solo colonne consentite', () {
      expect(
        migrationSql,
        contains(
          'GRANT SELECT\n'
          'ON TABLE public.transaction_categories\n'
          'TO authenticated;',
        ),
      );
      expect(
        migrationSql,
        isNot(
          contains('GRANT SELECT, INSERT ON public.transaction_categories'),
        ),
      );
      expect(
        migrationSql,
        isNot(
          contains(
            'GRANT SELECT, INSERT\nON TABLE public.transaction_categories',
          ),
        ),
      );

      expect(
        migrationSql,
        contains(
          'GRANT INSERT (\n'
          '  company_id,\n'
          '  name,\n'
          '  kind,\n'
          '  is_active\n'
          ')\n'
          'ON TABLE public.transaction_categories\n'
          'TO authenticated;',
        ),
      );

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

      expect(
        migrationSql,
        contains(
          'GRANT UPDATE (name, is_active)\n'
          'ON TABLE public.transaction_categories\n'
          'TO authenticated;',
        ),
      );
      expect(
        migrationSql,
        contains('REVOKE ALL ON public.transaction_categories FROM anon'),
      );
    });
  });
}
