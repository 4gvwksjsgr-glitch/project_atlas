import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260719000002_grant_private_schema_usage.sql', () {
    late String migrationSql;

    setUp(() {
      migrationSql = File(
        'supabase/migrations/20260719000002_grant_private_schema_usage.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('è additiva e concede soltanto USAGE sullo schema private', () {
      expect(migrationSql, contains('GRANT USAGE ON SCHEMA private'));
      expect(migrationSql, contains('TO authenticated'));
      expect(migrationSql, isNot(contains('CREATE OR REPLACE')));
      expect(migrationSql, isNot(contains('DROP ')));
      expect(migrationSql, isNot(contains('ALTER TABLE')));
    });

    test('revoca ALL da PUBLIC, anon e authenticated prima del GRANT', () {
      expect(
        migrationSql,
        contains('REVOKE ALL ON SCHEMA private FROM PUBLIC;'),
      );
      expect(migrationSql, contains('REVOKE ALL ON SCHEMA private FROM anon;'));
      expect(
        migrationSql,
        contains('REVOKE ALL ON SCHEMA private FROM authenticated;'),
      );
    });

    test('nessun CREATE, GRANT EXECUTE o privilegi su tabelle', () {
      expect(migrationSql, isNot(contains('GRANT CREATE')));
      expect(migrationSql, isNot(contains('GRANT ALL')));
      expect(migrationSql, isNot(contains('GRANT EXECUTE')));
      expect(migrationSql, isNot(contains('ON TABLE')));
      expect(migrationSql, isNot(contains('ON FUNCTION')));
      expect(migrationSql, isNot(contains('TO anon')));
      expect(migrationSql, isNot(contains('TO PUBLIC')));
    });
  });
}
