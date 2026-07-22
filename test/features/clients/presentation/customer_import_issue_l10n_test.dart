import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_issue.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_plan.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_row.dart';
import 'package:project_atlas/features/clients/presentation/customer_import_issue_l10n.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('it'));
  });

  group('customerImportIssueMessage', () {
    test('warning leadingZeroRisk in italiano senza chiave tecnica', () {
      const issue = CustomerImportIssue(
        severity: CustomerImportIssueSeverity.warning,
        code: 'leadingZeroRisk',
        sourceRow: 3,
      );
      final text = customerImportIssueMessage(l10n, issue);
      expect(
        text,
        'Riga 3 — Questa cella numerica potrebbe aver perso uno zero iniziale.',
      );
      expect(text, isNot(contains('leadingZeroRisk')));
    });

    test('errore missingName con prefisso riga', () {
      const issue = CustomerImportIssue(
        severity: CustomerImportIssueSeverity.error,
        code: 'missingName',
        sourceRow: 6,
      );
      expect(
        customerImportIssueMessage(l10n, issue),
        'Riga 6 — Nome o ragione sociale mancante.',
      );
    });

    test('duplicato email file e tenant senza PII', () {
      expect(
        customerImportIssueMessage(
          l10n,
          const CustomerImportIssue(
            severity: CustomerImportIssueSeverity.warning,
            code: 'duplicateEmailInFile',
            sourceRow: 2,
          ),
        ),
        'Riga 2 — Email duplicata nel file: la riga verrà esclusa.',
      );
      expect(
        customerImportIssueMessage(
          l10n,
          const CustomerImportIssue(
            severity: CustomerImportIssueSeverity.warning,
            code: 'duplicateEmailInTenant',
            sourceRow: 4,
          ),
        ),
        startsWith('Riga 4 — Email già presente tra i clienti dell'),
      );
      expect(
        customerImportIssueMessage(
          l10n,
          const CustomerImportIssue(
            severity: CustomerImportIssueSeverity.warning,
            code: 'duplicateEmailInTenant',
            sourceRow: 4,
          ),
        ),
        isNot(contains('@')),
      );
    });

    test('tutti i codici noti hanno messaggio italiano senza enum.name', () {
      const codes = <String>[
        'leadingZeroRisk',
        'duplicateEmailInFile',
        'duplicateEmailInTenant',
        'duplicateEmailInDatabase',
        'missingName',
        'invalidEmail',
        'nameTooLong',
        'emailTooLong',
        'phoneTooLong',
        'notesTooLong',
        'formulaCell',
        'formulaNotSupported',
        'invalidCellType',
        'similarName',
        'duplicateNameWarning',
      ];
      for (final code in codes) {
        final text = customerImportIssueMessage(
          l10n,
          CustomerImportIssue(
            severity: CustomerImportIssueSeverity.error,
            code: code,
            sourceRow: 1,
          ),
        );
        expect(text, isNot(contains(code)), reason: code);
        expect(text, startsWith('Riga 1 — '), reason: code);
        expect(text.length, greaterThan('Riga 1 — '.length), reason: code);
      }
    });

    test('codice sconosciuto non mostra la chiave tecnica', () {
      final text = customerImportIssueMessage(
        l10n,
        const CustomerImportIssue(
          severity: CustomerImportIssueSeverity.error,
          code: 'someInternalCodeXYZ',
          sourceRow: 9,
        ),
      );
      expect(text, 'Riga 9 — Problema nella riga.');
      expect(text, isNot(contains('someInternalCodeXYZ')));
    });
  });

  group('anteprima conteggi invariati', () {
    test('plan summary counts non dipendono dalla localizzazione issue', () {
      final plan = CustomerImportPlan(
        readCount: 5,
        validToImport: 2,
        skippedDuplicates: 1,
        errorRows: 1,
        emptyIgnored: 1,
        warnings: 2,
        rowsToImport: const [],
        excludedDuplicates: const [
          CustomerImportExcludedDuplicate(sourceRow: 3),
        ],
        rows: [
          CustomerImportRow(
            sourceRow: 2,
            rawCells: const ['A'],
            name: 'A',
            issues: const [
              CustomerImportIssue(
                severity: CustomerImportIssueSeverity.warning,
                code: 'leadingZeroRisk',
                sourceRow: 2,
              ),
            ],
          ),
          CustomerImportRow(
            sourceRow: 3,
            rawCells: const ['B'],
            name: 'B',
            email: 'b@example.test',
            issues: const [
              CustomerImportIssue(
                severity: CustomerImportIssueSeverity.warning,
                code: 'duplicateEmailInFile',
                sourceRow: 3,
              ),
            ],
          ),
          CustomerImportRow(
            sourceRow: 4,
            rawCells: const [''],
            issues: const [
              CustomerImportIssue(
                severity: CustomerImportIssueSeverity.error,
                code: 'missingName',
                sourceRow: 4,
              ),
            ],
          ),
        ],
      );

      expect(plan.readCount, 5);
      expect(plan.validToImport, 2);
      expect(plan.skippedDuplicates, 1);
      expect(plan.errorRows, 1);
      expect(plan.emptyIgnored, 1);
      expect(plan.warnings, 2);

      final subtitle = customerImportIssuesSubtitle(l10n, plan.rows[2].issues);
      expect(subtitle, contains('Nome o ragione sociale mancante'));
      expect(subtitle, isNot(contains('missingName')));
    });
  });

  group('UI preview / wizard', () {
    test('schermata anteprima non stampa issue.code grezzi', () {
      final source = File(
        'lib/features/clients/presentation/screens/customer_import_screen.dart',
      ).readAsStringSync();
      expect(source, contains('customerImportIssuesSubtitle'));
      expect(source, isNot(contains('.map((i) => i.code)')));
      expect(source, isNot(contains("issues.map((i) => i.code)")));
    });

    testWidgets('messaggi issue in anteprima senza chiavi tecniche', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('it'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final loc = AppLocalizations.of(context);
              final subtitle = customerImportIssuesSubtitle(loc, const [
                CustomerImportIssue(
                  severity: CustomerImportIssueSeverity.error,
                  code: 'missingName',
                  sourceRow: 6,
                ),
                CustomerImportIssue(
                  severity: CustomerImportIssueSeverity.warning,
                  code: 'duplicateEmailInFile',
                  sourceRow: 6,
                ),
              ]);
              return Scaffold(
                body: ListTile(
                  title: Text(loc.customersImportPreviewRowTitle(6, 'errore')),
                  subtitle: Text(subtitle),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Riga 6 · errore'), findsOneWidget);
      expect(
        find.textContaining('Nome o ragione sociale mancante'),
        findsOneWidget,
      );
      expect(find.textContaining('Email duplicata nel file'), findsOneWidget);
      expect(find.textContaining('missingName'), findsNothing);
      expect(find.textContaining('duplicateEmailInFile'), findsNothing);
    });
  });
}
