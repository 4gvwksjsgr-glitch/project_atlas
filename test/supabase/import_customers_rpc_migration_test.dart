import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _plpgsqlBody(String migrationSql) {
  final start = migrationSql.indexOf('AS \$\$');
  final end = migrationSql.lastIndexOf('\$\$;');
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return migrationSql.substring(start, end + 3);
}

/// Test strutturali della migration RPC (sempre eseguibili senza DB).
///
/// I test comportamentali SQL sono in
/// [import_customers_rpc_behavior_test.dart] e richiedono Supabase locale.
void main() {
  group('20260720000001_import_customers_rpc.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260720000001_import_customers_rpc.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('definisce import_customers SECURITY INVOKER', () {
      expect(migrationSql, contains('public.import_customers'));
      expect(migrationSql, contains('SECURITY INVOKER'));
      expect(migrationSql, isNot(contains('SECURITY DEFINER')));
      expect(migrationSql, contains('VOLATILE'));
      expect(migrationSql, contains("SET search_path = ''"));
    });

    test('valida ruolo, limiti e company_id dalla funzione', () {
      expect(migrationSql, contains('private.has_company_role'));
      expect(migrationSql, contains("ARRAY['owner', 'admin', 'manager']"));
      expect(migrationSql, contains('rows count must be between 1 and 500'));
      expect(migrationSql, contains('p_company_id'));
      expect(migrationSql, contains('INSERT INTO public.clients'));
      expect(migrationSql, contains('company_id = p_company_id'));
      expect(migrationSql, contains('pg_advisory_xact_lock'));
    });

    test('valida source_row intero senza cast troncante', () {
      expect(
        migrationSql,
        contains("jsonb_typeof(v_elem->'source_row') <> 'number'"),
      );
      expect(migrationSql, contains(r"v_source_row_raw !~ '^[0-9]+$'"));
      expect(
        migrationSql,
        contains('trunc(v_source_row_num) <> v_source_row_num'),
      );
      expect(migrationSql, contains('2147483647'));
      expect(migrationSql, contains('source_row must be a positive integer'));
      expect(migrationSql, contains('duplicate source_row in payload'));
      expect(migrationSql, isNot(contains("(v_elem->>'source_row')::INTEGER")));
    });

    test('rifiuta company_id e chiavi inattese prima dell INSERT', () {
      expect(
        migrationSql,
        contains("company_id must not be present in row payload"),
      );
      expect(migrationSql, contains('unexpected field in row payload'));
      expect(migrationSql, contains('each row must be a JSON object'));
      final insertIndex = migrationSql.indexOf(
        'INSERT INTO public.clients (company_id, name, email, phone, notes)',
      );
      final companyIdReject = migrationSql.indexOf(
        "company_id must not be present in row payload",
      );
      final unknownKey = migrationSql.indexOf(
        'unexpected field in row payload',
      );
      final sourceRowInt = migrationSql.indexOf(
        'source_row must be a positive integer',
      );
      expect(insertIndex, greaterThan(0));
      expect(companyIdReject, lessThan(insertIndex));
      expect(unknownKey, lessThan(insertIndex));
      expect(sourceRowInt, lessThan(insertIndex));
      expect('INSERT INTO public.clients'.allMatches(migrationSql).length, 1);
    });

    test(
      'documenta deduplicazione best effort dello Step 10A (non garanzia DB)',
      () {
        expect(migrationSql, contains('best effort dello Step 10A'));
        expect(migrationSql, contains('Non è garanzia database'));
        expect(migrationSql, contains('non esiste indice univoco'));
        expect(migrationSql, contains('Step 10B'));
        expect(migrationSql, isNot(contains('UNIQUE INDEX')));
        expect(migrationSql, isNot(contains('CREATE UNIQUE INDEX')));
      },
    );

    test(
      'restituisce conteggi senza PII e privilegi EXECUTE solo authenticated',
      () {
        expect(migrationSql, contains('inserted_count BIGINT'));
        expect(migrationSql, contains('skipped_duplicate_count BIGINT'));
        expect(migrationSql, contains('skipped_source_rows INTEGER[]'));
        expect(migrationSql, isNot(contains('RETURNS TABLE (\n  name')));
        expect(
          migrationSql,
          contains(
            'REVOKE ALL\n'
            'ON FUNCTION public.import_customers(UUID, JSONB)\n'
            'FROM PUBLIC;',
          ),
        );
        expect(
          migrationSql,
          contains(
            'REVOKE ALL\n'
            'ON FUNCTION public.import_customers(UUID, JSONB)\n'
            'FROM anon;',
          ),
        );
        expect(
          migrationSql,
          contains(
            'GRANT EXECUTE\n'
            'ON FUNCTION public.import_customers(UUID, JSONB)\n'
            'TO authenticated;',
          ),
        );
        expect(migrationSql, isNot(contains('ON TABLE')));
        expect(migrationSql, isNot(contains('GRANT DELETE')));
      },
    );

    test('messaggi errore senza campi PII', () {
      expect(migrationSql.toLowerCase(), isNot(contains('email address')));
      expect(migrationSql, isNot(contains('RAISE EXCEPTION \'%\' || v_name')));
      expect(migrationSql, isNot(contains('|| v_email')));
      expect(migrationSql, isNot(contains('|| v_phone')));
      expect(migrationSql, isNot(contains('|| v_notes')));
    });

    test('00001 crea TEMP TABLE ON COMMIT DROP (causa storica 42P07)', () {
      expect(migrationSql, contains('CREATE TEMP TABLE tmp_import_customers'));
      expect(migrationSql, contains('ON COMMIT DROP'));
      expect(migrationSql, isNot(contains('DROP TABLE IF EXISTS')));
    });
  });

  group('20260720000002_fix_import_customers_reentrancy.sql', () {
    late String migration00001;
    late String migration00002;

    setUp(() {
      migration00001 = File(
        'supabase/migrations/20260720000001_import_customers_rpc.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      migration00002 = File(
        'supabase/migrations/20260720000002_fix_import_customers_reentrancy.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test(
      '00001 resta invariata e 00002 la sostituisce con CREATE OR REPLACE',
      () {
        expect(
          migration00001,
          contains('CREATE OR REPLACE FUNCTION public.import_customers('),
        );
        expect(
          migration00002,
          contains('CREATE OR REPLACE FUNCTION public.import_customers('),
        );
        expect(
          migration00001,
          contains('CREATE TEMP TABLE tmp_import_customers'),
        );
        final body00002 = _plpgsqlBody(migration00002);
        expect(body00002, isNot(contains('CREATE TEMP TABLE')));
        expect(body00002, isNot(contains('CREATE TEMPORARY TABLE')));
        expect(body00002, isNot(contains('tmp_import_customers')));
        expect(migration00002, contains('v_staging JSONB'));
      },
    );

    test('correzione evita collisioni tabelle temporanee (reentrancy)', () {
      final body00002 = _plpgsqlBody(migration00002);
      expect(body00002, isNot(contains('tmp_import_customers')));
      expect(body00002, isNot(contains('ON COMMIT DROP')));
      expect(body00002, isNot(contains('DROP TABLE')));
      expect(body00002, isNot(contains('EXECUTE')));
      expect(migration00002, contains('jsonb_array_elements(v_staging)'));
      expect(
        migration00002,
        contains(
          'pg_advisory_xact_lock(hashtextextended(p_company_id::text, 0))',
        ),
      );
    });

    test('nessun SECURITY DEFINER; INVOKER + search_path + VOLATILE', () {
      expect(migration00002, contains('SECURITY INVOKER'));
      expect(migration00002, isNot(contains('SECURITY DEFINER')));
      expect(migration00002, contains('VOLATILE'));
      expect(migration00002, contains("SET search_path = ''"));
    });

    test('privilegi invariati e nessun nuovo privilegio sulle tabelle', () {
      expect(
        migration00002,
        contains(
          'REVOKE ALL ON FUNCTION public.import_customers(UUID, JSONB)\n'
          'FROM PUBLIC;',
        ),
      );
      expect(
        migration00002,
        contains(
          'REVOKE ALL ON FUNCTION public.import_customers(UUID, JSONB)\n'
          'FROM anon;',
        ),
      );
      expect(
        migration00002,
        contains(
          'REVOKE ALL ON FUNCTION public.import_customers(UUID, JSONB)\n'
          'FROM authenticated;',
        ),
      );
      expect(
        migration00002,
        contains(
          'GRANT EXECUTE ON FUNCTION public.import_customers(UUID, JSONB)\n'
          'TO authenticated;',
        ),
      );
      expect(migration00002, isNot(contains('ON TABLE')));
      expect(migration00002, isNot(contains('GRANT SELECT')));
      expect(migration00002, isNot(contains('GRANT INSERT')));
      expect(migration00002, isNot(contains('GRANT UPDATE')));
      expect(migration00002, isNot(contains('GRANT DELETE')));
      expect(migration00002, isNot(contains('GRANT ALL')));
    });

    test(
      'conserva auth, ruoli, validazione, atomicità e ritorno senza PII',
      () {
        expect(migration00002, contains('auth.uid()'));
        expect(migration00002, contains('private.has_company_role'));
        expect(migration00002, contains("ARRAY['owner', 'admin', 'manager']"));
        expect(
          migration00002,
          contains('rows count must be between 1 and 500'),
        );
        expect(migration00002, contains('INSERT INTO public.clients'));
        expect(
          'INSERT INTO public.clients'.allMatches(migration00002).length,
          1,
        );
        expect(migration00002, contains('inserted_count BIGINT'));
        expect(migration00002, contains('skipped_duplicate_count BIGINT'));
        expect(migration00002, contains('skipped_source_rows INTEGER[]'));
        expect(migration00002, contains('best effort dello Step 10A'));
        expect(migration00002, isNot(contains('|| v_email')));
        expect(migration00002, isNot(contains('|| v_phone')));
        expect(migration00002, isNot(contains('|| v_notes')));
      },
    );
  });
}
