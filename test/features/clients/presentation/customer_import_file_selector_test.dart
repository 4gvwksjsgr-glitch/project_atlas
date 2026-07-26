import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/di/providers.dart';
import 'package:project_atlas/core/files/app_file_pick_result.dart';
import 'package:project_atlas/core/files/app_file_picker.dart';
import 'package:project_atlas/core/files/selected_app_file.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_sheet.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_source.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_import_parser.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_import_providers.dart';
import 'package:project_atlas/features/clients/presentation/screens/customer_import_screen.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _FakePicker implements AppFilePicker {
  _FakePicker(this.result);

  AppFilePickResult result;
  var customerCalls = 0;

  @override
  Future<AppFilePickResult> pickCustomerImportFile() async {
    customerCalls += 1;
    return result;
  }

  @override
  Future<AppFilePickResult> pickDocumentUploadFile() async {
    return const AppFilePickCancelled();
  }
}

class _FakeParser implements CustomerImportFileParser {
  String? lastFileName;
  Uint8List? lastBytes;

  @override
  Future<CustomerImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    lastFileName = fileName;
    lastBytes = bytes;
    final kind = fileName.toLowerCase().endsWith('.xlsx')
        ? CustomerImportSourceKind.xlsx
        : CustomerImportSourceKind.csv;
    return CustomerImportSource(
      fileName: fileName,
      byteLength: bytes.length,
      kind: kind,
      sheets: [CustomerImportSheet(name: 'Foglio1', rowCount: 1)],
      selectedSheet: 'Foglio1',
      selectedTable: CustomerImportTable(
        headers: const ['Nome', 'Email'],
        dataRows: const [
          ['Ada', 'ada@example.test'],
        ],
      ),
    );
  }
}

ActiveCompanyContext _owner() {
  return const ActiveCompanyContext(
    companyId: 'c1',
    companyName: 'Acme',
    companySlug: 'acme',
    role: CompanyRole.owner,
    membershipId: 'm1',
  );
}

void main() {
  testWidgets('import clienti: CSV selezionato passa bytes al parser', (
    tester,
  ) async {
    final bytes = Uint8List.fromList('Nome,Email\nAda,a@b.c'.codeUnits);
    final picker = _FakePicker(
      AppFilePickSuccess(
        SelectedAppFile(
          name: 'clienti.csv',
          extension: 'csv',
          mimeType: 'text/csv',
          size: bytes.length,
          bytes: bytes,
        ),
      ),
    );
    final parser = _FakeParser();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          customerImportFileParserProvider.overrideWithValue(parser),
          appFilePickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CustomerImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seleziona file CSV o XLSX'));
    await tester.pumpAndSettle();

    expect(picker.customerCalls, 1);
    expect(parser.lastFileName, 'clienti.csv');
    expect(parser.lastBytes, bytes);
  });

  testWidgets('import clienti: XLSX selezionato passa bytes al parser', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
    final picker = _FakePicker(
      AppFilePickSuccess(
        SelectedAppFile(
          name: 'clienti.xlsx',
          extension: 'xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          size: bytes.length,
          bytes: bytes,
        ),
      ),
    );
    final parser = _FakeParser();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          customerImportFileParserProvider.overrideWithValue(parser),
          appFilePickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CustomerImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seleziona file CSV o XLSX'));
    await tester.pumpAndSettle();

    expect(parser.lastFileName, 'clienti.xlsx');
    expect(parser.lastBytes, bytes);
  });

  testWidgets('import clienti: selezione annullata non mostra errore', (
    tester,
  ) async {
    final picker = _FakePicker(const AppFilePickCancelled());
    final parser = _FakeParser();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCompanyProvider.overrideWithValue(_owner()),
          customerImportFileParserProvider.overrideWithValue(parser),
          appFilePickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CustomerImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Seleziona file CSV o XLSX'));
    await tester.pumpAndSettle();

    expect(parser.lastBytes, isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Seleziona file CSV o XLSX'), findsOneWidget);
  });
}
