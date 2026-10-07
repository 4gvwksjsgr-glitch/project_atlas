import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/di/providers.dart';
import 'package:project_atlas/core/files/app_file_pick_result.dart';
import 'package:project_atlas/core/files/app_file_picker.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transaction_import_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _FakePicker implements AppFilePicker {
  var transactionCalls = 0;
  TabularImportFileFormat? lastTransactionFormat;

  @override
  Future<AppFilePickResult> pickCustomerImportFile({
    TabularImportFileFormat? format,
  }) async {
    return const AppFilePickCancelled();
  }

  @override
  Future<AppFilePickResult> pickTransactionImportFile({
    TabularImportFileFormat? format,
  }) async {
    transactionCalls += 1;
    lastTransactionFormat = format;
    return const AppFilePickCancelled();
  }

  @override
  Future<AppFilePickResult> pickDocumentUploadFile() async {
    return const AppFilePickCancelled();
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

Future<void> _pumpImportScreen(
  WidgetTester tester, {
  required _FakePicker picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeCompanyProvider.overrideWithValue(_owner()),
        appFilePickerProvider.overrideWithValue(picker),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TransactionImportScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _withAndroid(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('Android: tap pick shows format choice before calling picker', (
    tester,
  ) async {
    await _withAndroid(() async {
      final picker = _FakePicker();

      await _pumpImportScreen(tester, picker: picker);

      await tester.tap(find.text('Seleziona file CSV o XLSX'));
      await tester.pumpAndSettle();

      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Excel (.xlsx)'), findsOneWidget);
      expect(picker.transactionCalls, 0);
    });
  });

  testWidgets('Android: choosing CSV passes format csv', (tester) async {
    await _withAndroid(() async {
      final picker = _FakePicker();

      await _pumpImportScreen(tester, picker: picker);

      await tester.tap(find.text('Seleziona file CSV o XLSX'));
      await tester.pumpAndSettle();
      expect(picker.transactionCalls, 0);

      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();

      expect(picker.transactionCalls, 1);
      expect(picker.lastTransactionFormat, TabularImportFileFormat.csv);
    });
  });

  testWidgets('Android: choosing Excel passes format xlsx', (tester) async {
    await _withAndroid(() async {
      final picker = _FakePicker();

      await _pumpImportScreen(tester, picker: picker);

      await tester.tap(find.text('Seleziona file CSV o XLSX'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excel (.xlsx)'));
      await tester.pumpAndSettle();

      expect(picker.transactionCalls, 1);
      expect(picker.lastTransactionFormat, TabularImportFileFormat.xlsx);
    });
  });

  testWidgets('Android: dismissing format choice does not call picker', (
    tester,
  ) async {
    await _withAndroid(() async {
      final picker = _FakePicker();

      await _pumpImportScreen(tester, picker: picker);

      await tester.tap(find.text('Seleziona file CSV o XLSX'));
      await tester.pumpAndSettle();
      expect(picker.transactionCalls, 0);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(picker.transactionCalls, 0);
      expect(find.text('CSV'), findsNothing);
    });
  });
}
