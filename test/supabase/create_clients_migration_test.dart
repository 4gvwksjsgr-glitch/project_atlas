import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260717000001_create_clients.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260717000001_create_clients.sql',
      ).readAsStringSync();
    });

    test('crea tabella clients con colonne e vincoli richiesti', () {
      expect(migrationSql, contains('CREATE TABLE public.clients'));
      expect(migrationSql, contains('company_id'));
      expect(
        migrationSql,
        contains('REFERENCES public.companies(id) ON DELETE CASCADE'),
      );
      expect(migrationSql, contains('clients_name_not_empty'));
      expect(migrationSql, contains('idx_clients_company_id'));
      expect(migrationSql, contains('idx_clients_company_name'));
      expect(
        migrationSql,
        contains('EXECUTE FUNCTION public.set_updated_at()'),
      );
    });

    test('abilita FORCE RLS e policy SELECT/INSERT/UPDATE senza DELETE', () {
      expect(migrationSql, contains('ENABLE ROW LEVEL SECURITY'));
      expect(migrationSql, contains('FORCE ROW LEVEL SECURITY'));
      expect(migrationSql, contains('clients_select_member'));
      expect(migrationSql, contains('clients_insert_owner_admin_manager'));
      expect(migrationSql, contains('clients_update_owner_admin_manager'));
      expect(
        migrationSql,
        contains('private.is_company_member(company_id, auth.uid())'),
      );
      expect(
        migrationSql,
        contains("ARRAY['owner', 'admin', 'manager']::public.company_role[]"),
      );
      expect(migrationSql, isNot(contains('FOR DELETE')));
      expect(
        migrationSql,
        contains('REVOKE DELETE ON public.clients FROM authenticated'),
      );
    });

    test('concede soltanto SELECT INSERT UPDATE a authenticated', () {
      expect(
        migrationSql,
        contains(
          'GRANT SELECT, INSERT, UPDATE ON public.clients TO authenticated',
        ),
      );
      expect(migrationSql, contains('REVOKE ALL ON public.clients FROM anon'));
    });
  });
}
