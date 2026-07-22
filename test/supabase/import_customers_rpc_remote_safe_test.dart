import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('import_customers_rpc_remote_safe.sql', () {
    late String sql;

    setUp(() {
      sql = File(
        'supabase/tests/import_customers_rpc_remote_safe.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('inizia con BEGIN e termina con ROLLBACK senza COMMIT', () {
      expect(sql.contains('BEGIN;'), isTrue);
      expect(sql.trimRight().endsWith('ROLLBACK;'), isTrue);
      expect(sql, isNot(contains('COMMIT;')));
      final code = sql
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      expect(code, isNot(contains('COMMIT;')));
      expect(code, contains('ON COMMIT DROP'));
    });

    test('usa TEMP TABLE risultati e cattura errori attesi', () {
      expect(sql, contains('CREATE TEMP TABLE test_results'));
      expect(sql, contains('ON COMMIT DROP'));
      expect(sql, contains('WHEN SQLSTATE \'22023\' THEN'));
      expect(sql, contains('WHEN SQLSTATE \'28000\' THEN'));
      expect(sql, contains('WHEN SQLSTATE \'42501\' THEN'));
      expect(sql, contains('WHEN OTHERS THEN'));
      expect(
        sql,
        contains('SELECT test_name, passed, error_code, safe_message'),
      );
      expect(sql, contains('COUNT(*) FILTER (WHERE passed)'));
    });

    test('simula auth e crea soltanto seed temporanei', () {
      expect(sql, contains('SET LOCAL ROLE authenticated'));
      expect(sql, contains("set_config('request.jwt.claim.sub'"));
      expect(sql, contains('gen_random_uuid()'));
      expect(sql, contains('example.invalid'));
      expect(sql, contains('best effort dello Step 10A'));
      expect(sql, contains('Temporary auth.users rows are required'));
    });

    test('non usa DELETE/UPDATE su dati preesistenti né credenziali reali', () {
      final code = sql
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n')
          .toUpperCase();
      expect(code, isNot(contains('DELETE FROM')));
      expect(code, isNot(contains('UPDATE ')));
      expect(sql, isNot(contains('service_role')));
      expect(sql, isNot(contains('eyJ'))); // JWT-looking
      expect(sql, isNot(contains('SUPABASE_SERVICE')));
      // No hardcoded real-looking UUID constants (nil instance id is ok for auth.users).
      final uuidLiteral = RegExp(
        r"[^0][0-9a-fA-F]{7}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
      );
      expect(uuidLiteral.hasMatch(sql), isFalse);
    });

    test('non stampa payload o campi PII nei risultati', () {
      expect(sql, contains("safe_message TEXT"));
      expect(sql, isNot(contains('RAISE NOTICE')));
      expect(sql, isNot(contains('RAISE EXCEPTION \'%\' ||')));
      expect(sql, isNot(contains('|| v_email')));
      expect(sql, isNot(contains('|| v_phone')));
      expect(sql, isNot(contains('|| v_notes')));
      // Result projection excludes personal fields.
      expect(
        sql,
        contains('SELECT test_name, passed, error_code, safe_message'),
      );
      expect(sql, isNot(contains('SELECT name, email')));
    });

    test('espone run_marker tecnico per verifica residui post-ROLLBACK', () {
      expect(sql, contains("v_run_marker TEXT :="));
      expect(sql, contains("'step10a-remote-'"));
      expect(sql, contains("'run_marker'"));
      expect(sql, contains('SELECT safe_message AS run_marker'));
      expect(sql, contains('example.invalid'));
    });

    test('copre i casi comportamentali richiesti', () {
      for (final marker in const [
        'not_authenticated',
        'employee_rejected',
        'owner_authorized',
        'admin_authorized',
        'manager_authorized',
        'company_id_null',
        'payload_null',
        'payload_not_array',
        'empty_array',
        'more_than_500',
        'element_not_object',
        'unknown_key',
        'company_id_in_payload',
        'source_row_missing',
        'source_row_string',
        'source_row_decimal',
        'source_row_zero',
        'source_row_negative',
        'source_row_duplicate',
        'name_missing',
        'name_blank',
        'email_wrong_type',
        'phone_wrong_type',
        'notes_wrong_type',
        'length_limits',
        'atomic_failure',
        'company_id_from_param',
        'tenant_isolation',
        'duplicate_email_payload',
        'duplicate_email_tenant',
        'email_other_tenant_ok',
        'rows_without_email',
        'counts_coherent',
        'result_no_pii',
        'skipped_source_rows_integers',
        'residue_in_txn_',
        'run_marker',
      ]) {
        expect(sql, contains(marker), reason: 'manca caso $marker');
      }
    });
  });

  group('import_customers_rpc_behavior.sql (locale)', () {
    test('resta LOCAL DATABASE ONLY — NEVER RUN ON REMOTE', () {
      final sql = File(
        'supabase/tests/import_customers_rpc_behavior.sql',
      ).readAsStringSync();
      expect(sql, contains('LOCAL DATABASE ONLY — NEVER RUN ON REMOTE'));
      expect(sql.toLowerCase(), contains('db reset'));
      expect(sql.toLowerCase(), contains('never run on remote'));
    });
  });
}
