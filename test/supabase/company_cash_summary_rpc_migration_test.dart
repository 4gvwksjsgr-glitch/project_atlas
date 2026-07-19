import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260719000001_company_cash_summary_rpc.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260719000001_company_cash_summary_rpc.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('è additiva e definisce get_company_cash_summary', () {
      expect(migrationSql, contains('CREATE OR REPLACE FUNCTION'));
      expect(migrationSql, contains('public.get_company_cash_summary'));
      expect(migrationSql, isNot(contains('DROP TABLE')));
      expect(migrationSql, isNot(contains('ALTER TABLE public.transactions')));
    });

    test('SECURITY INVOKER senza SECURITY DEFINER', () {
      expect(migrationSql, contains('SECURITY INVOKER'));
      expect(migrationSql, isNot(contains('SECURITY DEFINER')));
      expect(migrationSql, contains('LANGUAGE plpgsql'));
      expect(migrationSql, contains('STABLE'));
      expect(migrationSql, contains("SET search_path = ''"));
    });

    test('valida company_id e intervallo mese semiaperto', () {
      expect(migrationSql, contains('p_company_id IS NULL'));
      expect(migrationSql, contains('p_month_start IS NULL'));
      expect(migrationSql, contains('p_next_month_start IS NULL'));
      expect(migrationSql, contains('p_month_start >= p_next_month_start'));
      expect(migrationSql, contains('t.occurred_on >= p_month_start'));
      expect(migrationSql, contains('t.occurred_on < p_next_month_start'));
      expect(migrationSql, isNot(contains('p_month_end')));
    });

    test('membership check e filtro company_id obbligatorio', () {
      expect(
        migrationSql,
        contains('private.is_company_member(p_company_id, auth.uid())'),
      );
      expect(migrationSql, contains('auth.uid() IS NULL'));
      expect(migrationSql, contains('WHERE t.company_id = p_company_id'));
    });

    test('importi restituiti come TEXT da SUM NUMERIC', () {
      expect(migrationSql, contains('total_income TEXT'));
      expect(migrationSql, contains('total_expense TEXT'));
      expect(migrationSql, contains('month_income TEXT'));
      expect(migrationSql, contains('month_expense TEXT'));
      expect(migrationSql, contains('movement_count BIGINT'));
      expect(migrationSql, contains('month_movement_count BIGINT'));
      expect(migrationSql, contains('COALESCE('));
      expect(migrationSql, contains(')::TEXT'));
      expect(migrationSql, contains('SUM(t.amount)'));
    });

    test('REVOKE PUBLIC/anon e EXECUTE solo authenticated', () {
      expect(
        migrationSql,
        contains(
          'REVOKE ALL\n'
          'ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)\n'
          'FROM PUBLIC;',
        ),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL\n'
          'ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)\n'
          'FROM anon;',
        ),
      );
      expect(
        migrationSql,
        contains(
          'REVOKE ALL\n'
          'ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)\n'
          'FROM authenticated;',
        ),
      );
      expect(
        migrationSql,
        contains(
          'GRANT EXECUTE\n'
          'ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)\n'
          'TO authenticated;',
        ),
      );
      expect(migrationSql, isNot(contains('TO anon')));
      expect(migrationSql, isNot(contains('GRANT ALL')));
    });

    test('non modifica privilegi delle tabelle', () {
      expect(migrationSql, isNot(contains('ON TABLE')));
      expect(migrationSql, isNot(contains('ALTER DEFAULT PRIVILEGES')));
    });
  });
}
