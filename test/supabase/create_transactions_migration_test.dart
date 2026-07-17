import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260718000001_create_transactions.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260718000001_create_transactions.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('crea enum, unique clients e tabella transactions', () {
      expect(
        migrationSql,
        contains(
          "CREATE TYPE public.transaction_kind AS ENUM ('income', 'expense')",
        ),
      );
      expect(
        migrationSql,
        contains('ADD CONSTRAINT clients_company_id_id_unique'),
      );
      expect(migrationSql, contains('UNIQUE (company_id, id)'));
      expect(migrationSql, contains('CREATE TABLE public.transactions'));
      expect(migrationSql, contains('ON DELETE SET NULL (client_id)'));
    });

    test('indici, trigger updated_at e immutabilità company_id', () {
      expect(migrationSql, contains('idx_transactions_company_id'));
      expect(migrationSql, contains('idx_transactions_company_occurred_on'));
      expect(migrationSql, contains('idx_transactions_company_client'));
      expect(migrationSql, contains('set_transactions_updated_at'));
      expect(migrationSql, contains('public.set_updated_at()'));
      expect(
        migrationSql,
        contains('private.enforce_transactions_company_id_immutable'),
      );
      expect(migrationSql, contains("company_id cannot be changed"));
      expect(migrationSql, contains('trg_transactions_company_id_immutable'));
      expect(
        migrationSql,
        contains(
          'REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()\n'
          '  FROM PUBLIC',
        ),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()\n'
          '  FROM anon',
        ),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()\n'
          '  FROM authenticated',
        ),
      );
    });

    test('RLS SELECT/INSERT/UPDATE senza DELETE', () {
      expect(migrationSql, contains('FORCE ROW LEVEL SECURITY'));
      expect(migrationSql, contains('transactions_select_member'));
      expect(migrationSql, contains('transactions_insert_owner_admin_manager'));
      expect(migrationSql, contains('transactions_update_owner_admin_manager'));
      expect(migrationSql, isNot(contains('FOR DELETE')));
      expect(migrationSql, contains('private.is_company_member'));
      expect(migrationSql, contains('private.has_company_role'));
    });

    test('grant iniziali SELECT INSERT UPDATE, anon revocato', () {
      expect(
        migrationSql,
        contains('GRANT SELECT, INSERT, UPDATE ON public.transactions'),
      );
      expect(
        migrationSql,
        contains('REVOKE ALL ON public.transactions FROM anon'),
      );
      expect(
        migrationSql,
        contains('REVOKE DELETE ON public.transactions FROM authenticated'),
      );
      expect(migrationSql, isNot(contains('GRANT DELETE')));
      expect(migrationSql, isNot(contains('GRANT ALL')));
    });
  });
}
