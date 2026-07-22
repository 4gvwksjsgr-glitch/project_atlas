import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Suite comportamentale SQL di `import_customers`.
///
/// Esegue `supabase/tests/import_customers_rpc_behavior.sql` contro un
/// Postgres locale (Supabase CLI) se disponibile.
///
/// Limite ambiente: senza Docker / Supabase locale i casi restano definiti
/// nello script SQL ma non vengono eseguiti sul database. Nessun db push
/// remoto.
void main() {
  final sqlScript = File('supabase/tests/import_customers_rpc_behavior.sql');
  final supabaseExe = File('.tools/supabase/supabase.exe');

  var localDbAvailable = false;
  var skipReason =
      'Supabase/Docker locale non disponibile. '
      'Avviare con `.\\.tools\\supabase\\supabase.exe start` e '
      '`.\\.tools\\supabase\\supabase.exe db reset` per eseguire i '
      'test comportamentali RPC. Nessun collegamento al DB remoto.';

  setUpAll(() async {
    if (!sqlScript.existsSync()) {
      skipReason = 'Script SQL comportamentale assente';
      localDbAvailable = false;
      return;
    }
    if (!supabaseExe.existsSync()) {
      skipReason = 'CLI Supabase locale assente (.tools/supabase)';
      localDbAvailable = false;
      return;
    }

    final status = await Process.run(
      supabaseExe.path,
      ['status'],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    localDbAvailable = status.exitCode == 0;
    if (!localDbAvailable) {
      skipReason =
          'Supabase/Docker locale non disponibile '
          '(exit ${status.exitCode}). '
          'Avviare con `.\\.tools\\supabase\\supabase.exe start` e '
          '`.\\.tools\\supabase\\supabase.exe db reset` per eseguire i '
          'test comportamentali RPC. Nessun collegamento al DB remoto.';
    }
  });

  test('script comportamentale locale presente e marcato LOCAL ONLY', () {
    expect(sqlScript.existsSync(), isTrue);
    final sql = sqlScript.readAsStringSync();
    expect(sql, contains('LOCAL DATABASE ONLY — NEVER RUN ON REMOTE'));
    for (final marker in const [
      'not_authenticated',
      'company_id_null',
      'payload_null',
      'payload_not_array',
      'empty_array',
      'more_than_500',
      'employee_rejected',
      'owner_authorized',
      'admin_authorized',
      'manager_authorized',
      'element_not_object',
      'source_row_missing',
      'source_row_string',
      'source_row_decimal',
      'source_row_non_positive',
      'source_row_duplicate',
      'name_missing',
      'name_blank',
      'email_wrong_type',
      'phone_wrong_type',
      'notes_wrong_type',
      'length_limits',
      'company_id_in_payload',
      'unknown_key',
      'atomic_failure',
      'company_id_from_param',
      'tenant_isolation',
      'duplicate_email_payload',
      'duplicate_email_tenant',
      'email_other_tenant_ok',
      'rows_without_email',
      'result_no_pii',
      'counts_coherent',
      'advisory_lock',
      'best effort dello Step 10A',
    ]) {
      expect(sql, contains(marker), reason: 'manca caso $marker');
    }
  });

  test('esegue behavior SQL su database locale isolato', () async {
    if (!localDbAvailable) {
      markTestSkipped(skipReason);
      return;
    }

    // Apply migrations locally without remote push.
    final reset = await Process.run(
      supabaseExe.path,
      ['db', 'reset', '--yes'],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    expect(
      reset.exitCode,
      0,
      reason: 'db reset fallito: ${reset.stderr}\n${reset.stdout}',
    );

    final run = await Process.run(
      supabaseExe.path,
      ['db', 'query', '--local', '-f', sqlScript.path],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    if (run.exitCode != 0) {
      // Fallback: psql via DB URL from status if `db query` unsupported.
      final status = await Process.run(
        supabaseExe.path,
        ['status', '-o', 'env'],
        workingDirectory: Directory.current.path,
        runInShell: true,
      );
      final envOut = '${status.stdout}\n${status.stderr}';
      final match = RegExp(r'DB_URL=(.+)').firstMatch(envOut);
      expect(match, isNotNull, reason: 'DB_URL assente: $envOut');
      final dbUrl = match!.group(1)!.trim();
      final psql = await Process.run(
        'psql',
        [dbUrl, '-v', 'ON_ERROR_STOP=1', '-f', sqlScript.path],
        workingDirectory: Directory.current.path,
        runInShell: true,
      );
      expect(
        psql.exitCode,
        0,
        reason:
            'behavior SQL fallito.\n'
            'db query: ${run.stderr}\n${run.stdout}\n'
            'psql: ${psql.stderr}\n${psql.stdout}',
      );
      expect(
        '${psql.stdout}\n${psql.stderr}',
        contains('IMPORT_CUSTOMERS_BEHAVIOR_OK'),
      );
      return;
    }

    expect(
      '${run.stdout}\n${run.stderr}',
      contains('IMPORT_CUSTOMERS_BEHAVIOR_OK'),
    );
  });
}
