import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('20260726000001_create_documents.sql', () {
    late String sql;

    setUp(() {
      sql = File(
        'supabase/migrations/20260726000001_create_documents.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('crea tabella documents con vincoli richiesti', () {
      expect(sql, contains('CREATE TABLE public.documents'));
      expect(sql, contains('documents_title_trimmed'));
      expect(sql, contains('documents_mime_type_allowed'));
      expect(sql, contains('documents_size_bytes_max'));
      expect(sql, contains('CHECK (size_bytes <= 6291456)'));
      expect(sql, contains('documents_storage_path_matches_ids'));
      expect(sql, contains("storage_path ~"));
      expect(
        sql,
        contains(
          "'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'",
        ),
      );
      expect(sql, contains(r"'\.(pdf|jpg|png|webp)$'"));
      expect(sql, isNot(contains('storage_path LIKE')));
      expect(sql, isNot(contains('client_id')));
      expect(sql, isNot(contains('transaction_id')));
      expect(sql, isNot(contains('upload_status')));
      expect(sql, isNot(contains('storage_bucket')));
    });

    test('abilita FORCE RLS e policy senza DELETE', () {
      expect(sql, contains('FORCE ROW LEVEL SECURITY'));
      expect(sql, contains('documents_select_member'));
      expect(sql, contains('documents_insert_owner_admin_manager'));
      expect(sql, contains('documents_update_owner_admin_manager'));
      expect(sql, contains('Nessuna policy DELETE'));
    });
  });

  group('20260726000002_create_company_documents_storage.sql', () {
    late String sql;

    setUp(() {
      sql = File(
        'supabase/migrations/20260726000002_create_company_documents_storage.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('crea bucket privato con limiti', () {
      expect(sql, contains("'company-documents'"));
      expect(sql, contains('FALSE'));
      expect(sql, contains('6291456'));
      expect(sql, contains('application/pdf'));
      expect(sql, isNot(contains('ON CONFLICT')));
    });

    test('policy Storage SELECT INSERT DELETE senza UPDATE', () {
      expect(sql, contains('company_documents_select_member'));
      expect(sql, contains('company_documents_insert_owner_admin_manager'));
      expect(sql, contains('company_documents_delete_owner_admin_manager'));
      expect(sql, contains('Nessuna policy UPDATE'));
      expect(sql, contains('storage_uuid_path_segment'));
      expect(sql, contains('storage_company_documents_path_is_canonical'));
    });
  });

  group('20260726000003_harden_documents_privileges.sql', () {
    late String sql;

    setUp(() {
      sql = File(
        'supabase/migrations/20260726000003_harden_documents_privileges.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('least privilege su colonne', () {
      expect(sql, contains('REVOKE ALL ON TABLE public.documents FROM anon'));
      expect(sql, contains('GRANT SELECT'));
      expect(sql, contains('GRANT INSERT ('));
      expect(sql, contains('GRANT UPDATE ('));
      expect(sql, contains('title'));
      expect(sql, contains('is_archived'));
      expect(sql, isNot(contains('GRANT DELETE')));
    });
  });
}
