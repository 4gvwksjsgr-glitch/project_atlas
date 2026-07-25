import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260725000001_add_transactions_category_id.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260725000001_add_transactions_category_id.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('aggiunge colonna category_id nullable', () {
      expect(migrationSql, contains('ADD COLUMN category_id UUID NULL'));
      expect(
        migrationSql,
        contains('COMMENT ON COLUMN public.transactions.category_id'),
      );
    });

    test('FK composita con ON DELETE SET NULL (category_id)', () {
      expect(
        migrationSql,
        contains('ADD CONSTRAINT transactions_category_same_company_kind'),
      );
      expect(
        migrationSql,
        contains(
          'FOREIGN KEY (company_id, category_id, kind)\n'
          '  REFERENCES public.transaction_categories (company_id, id, kind)\n'
          '  ON DELETE SET NULL (category_id)',
        ),
      );
    });

    test('indice parziale company_id + category_id', () {
      expect(
        migrationSql,
        contains('CREATE INDEX idx_transactions_company_category'),
      );
      expect(
        migrationSql,
        contains(
          'ON public.transactions (company_id, category_id)\n'
          '  WHERE category_id IS NOT NULL',
        ),
      );
    });

    test('nessun GRANT/REVOKE e nessuna modifica a migration storiche', () {
      expect(migrationSql, isNot(contains('GRANT ')));
      expect(migrationSql, isNot(contains('REVOKE ')));
      expect(migrationSql, isNot(contains('ALTER POLICY')));
      expect(migrationSql, isNot(contains('CREATE POLICY')));
      expect(
        migrationSql,
        isNot(contains('20260718000001_create_transactions')),
      );
      expect(
        migrationSql,
        isNot(contains('20260724000001_create_transaction_categories')),
      );
    });
  });
}
