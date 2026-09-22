import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_file_parser.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_sheet.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_source.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_table.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_payload_row.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_result.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_row.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_import_repository.dart';
import 'package:project_atlas/features/transactions/domain/services/transaction_import_fingerprint.dart';
import 'package:project_atlas/features/transactions/domain/usecases/import_transactions.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_field.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_formats.dart';
import 'package:project_atlas/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_import_providers.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';

class _FakeParser implements TabularImportFileParser {
  _FakeParser(this.source);

  TabularImportSource source;
  String? lastPreferredSheet;

  @override
  Future<TabularImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    lastPreferredSheet = preferredSheet;
    return source;
  }
}

class _ThrowingParser implements TabularImportFileParser {
  _ThrowingParser(this.error);

  final Object error;

  @override
  Future<TabularImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    throw error;
  }
}

class _FakeImportRepo implements TransactionImportRepository {
  _FakeImportRepo({this.failure, this.gate});

  Result<TransactionImportResult>? result;
  Failure? failure;
  Completer<Result<TransactionImportResult>>? gate;

  int callCount = 0;
  final Completer<void> started = Completer<void>();

  String? lastCompanyId;
  String? lastFileName;
  String? lastSha256;
  String? lastFormat;
  List<TransactionImportPayloadRow> lastRows = const [];

  @override
  Future<Result<TransactionImportResult>> importTransactions({
    required String companyId,
    required String sourceFileName,
    required String sourceFileSha256,
    required String sourceFormat,
    required List<TransactionImportPayloadRow> rows,
  }) async {
    callCount += 1;
    lastCompanyId = companyId;
    lastFileName = sourceFileName;
    lastSha256 = sourceFileSha256;
    lastFormat = sourceFormat;
    lastRows = rows;

    if (!started.isCompleted) {
      started.complete();
    }
    if (gate != null) {
      return gate!.future;
    }
    if (failure != null) {
      return Error(failure!);
    }
    return result ?? Success(_resultWith(importedCount: rows.length));
  }
}

TransactionImportResult _resultWith({required int importedCount}) {
  return TransactionImportResult(
    batchId: '11111111-1111-4111-8111-111111111111',
    importedCount: importedCount,
    skippedInvalidCount: 0,
    skippedDuplicateCount: 0,
    transactionIds: List.generate(importedCount, (i) => 'tx-$i'),
  );
}

TabularImportSource _source({
  List<String> headers = const ['Data', 'Descrizione', 'Importo'],
  List<List<String?>>? dataRows,
  String fileName = 'movimenti.csv',
  TabularImportSourceKind kind = TabularImportSourceKind.csv,
  List<TabularImportSheet>? sheets,
  String? selectedSheet,
}) {
  final table = TabularImportTable(
    headers: headers,
    dataRows:
        dataRows ??
        [
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ],
  );
  return TabularImportSource(
    fileName: fileName,
    byteLength: 256,
    kind: kind,
    sheets:
        sheets ?? [TabularImportSheet(name: 'CSV', rowCount: table.rowCount)],
    selectedSheet: selectedSheet ?? 'CSV',
    selectedTable: table,
  );
}

CashTransaction _existingTransaction({
  String isoDate = '2026-03-04',
  TransactionKind kind = TransactionKind.income,
  String amount = '1500.00',
  String description = 'Incasso cliente',
}) {
  return CashTransaction(
    id: 'tx-existing',
    companyId: 'A',
    kind: kind,
    amount: MoneyAmount.fromCanonicalDecimal(amount),
    occurredOn: DateTime.parse(isoDate),
    description: description,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

ProviderContainer _container({
  required _FakeImportRepo repo,
  TabularImportFileParser? parser,
  List<CashTransaction> existing = const [],
  Override? existingOverride,
}) {
  return ProviderContainer(
    overrides: [
      transactionImportFileParserProvider.overrideWithValue(
        parser ?? _FakeParser(_source()),
      ),
      transactionImportRepositoryProvider.overrideWithValue(repo),
      importTransactionsUseCaseProvider.overrideWithValue(
        ImportTransactions(repo),
      ),
      existingOverride ??
          transactionImportExistingTransactionsProvider.overrideWith(
            (ref, companyId) async => existing,
          ),
      transactionsProvider.overrideWith(
        (ref, companyId) async => <CashTransaction>[],
      ),
    ],
  );
}

final _fileBytes = Uint8List.fromList([1, 2, 3, 4]);

Future<TransactionImportController> _prepareToConfirm(
  ProviderContainer container,
  String companyId, {
  String fileName = 'movimenti.csv',
}) async {
  final controller = container.read(
    transactionImportControllerProvider(companyId).notifier,
  );
  await controller.loadFile(fileName: fileName, bytes: _fileBytes);
  await controller.buildPlan();
  return controller;
}

void main() {
  group('TransactionImportController sessione e ciclo di vita', () {
    test('la family tiene separate azienda A e azienda B', () {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      container
          .read(transactionImportControllerProvider('A').notifier)
          .goToStep(TransactionImportWizardStep.pickFile);

      expect(
        container.read(transactionImportControllerProvider('A')).step,
        TransactionImportWizardStep.pickFile,
      );
      expect(
        container.read(transactionImportControllerProvider('B')).step,
        TransactionImportWizardStep.info,
      );
      expect(
        identical(
          container.read(transactionImportControllerProvider('A').notifier),
          container.read(transactionImportControllerProvider('B').notifier),
        ),
        isFalse,
      );
    });

    test('autoDispose azzera lo stato quando nessuno ascolta', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final sub = container.listen(
        transactionImportControllerProvider('A'),
        (_, _) {},
      );
      container
          .read(transactionImportControllerProvider('A').notifier)
          .goToStep(TransactionImportWizardStep.mapping);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(transactionImportControllerProvider('A')).step,
        TransactionImportWizardStep.info,
      );
    });

    test('reset rimuove file, sorgente, mapping e piano', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      expect(
        container.read(transactionImportControllerProvider('A')).plan,
        isNotNull,
      );

      controller.reset();
      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.fileBytes, isNull);
      expect(state.fileName, isNull);
      expect(state.fileSha256, isNull);
      expect(state.source, isNull);
      expect(state.mapping, isNull);
      expect(state.plan, isNull);
      expect(state.step, TransactionImportWizardStep.info);
    });

    test('logout: dispose del container elimina la sessione', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      await _prepareToConfirm(container, 'A');
      container.dispose();

      final next = _container(repo: repo);
      addTearDown(next.dispose);
      expect(next.read(transactionImportControllerProvider('A')).plan, isNull);
    });
  });

  group('TransactionImportController lettura file', () {
    test('file CSV valido porta al mapping con auto-associazione', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final controller = container.read(
        transactionImportControllerProvider('A').notifier,
      );
      await controller.loadFile(
        fileName: 'movimenti.csv',
        bytes: _fileBytes,
      );

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.mapping);
      expect(state.fileName, 'movimenti.csv');
      expect(state.sourceFormat, 'csv');
      expect(state.mapping!.fieldAt(0), TransactionImportField.date);
      expect(state.mapping!.fieldAt(1), TransactionImportField.description);
      expect(state.mapping!.fieldAt(2), TransactionImportField.signedAmount);
      expect(state.actionStatus, CompanyActionStatus.idle);
    });

    test('impronta del file calcolata sui byte originali', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      await container
          .read(transactionImportControllerProvider('A').notifier)
          .loadFile(fileName: 'movimenti.csv', bytes: _fileBytes);

      expect(
        container.read(transactionImportControllerProvider('A')).fileSha256,
        TransactionImportFingerprint.fileFingerprint(_fileBytes),
      );
    });

    test('XLSX multi-foglio chiede prima quale foglio importare', () async {
      final parser = _FakeParser(
        _source(
          fileName: 'anno.xlsx',
          kind: TabularImportSourceKind.xlsx,
          sheets: const [
            TabularImportSheet(name: 'Gennaio', rowCount: 1),
            TabularImportSheet(name: 'Febbraio', rowCount: 2),
          ],
          selectedSheet: 'Gennaio',
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      final controller = container.read(
        transactionImportControllerProvider('A').notifier,
      );
      await controller.loadFile(fileName: 'anno.xlsx', bytes: _fileBytes);

      expect(
        container.read(transactionImportControllerProvider('A')).step,
        TransactionImportWizardStep.pickSheet,
      );
      expect(
        container.read(transactionImportControllerProvider('A')).sourceFormat,
        'xlsx',
      );

      await controller.selectSheet('Febbraio');
      expect(parser.lastPreferredSheet, 'Febbraio');
      expect(
        container.read(transactionImportControllerProvider('A')).step,
        TransactionImportWizardStep.mapping,
      );
    });

    test('file oltre 2 MB respinto e byte rimossi', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      await container
          .read(transactionImportControllerProvider('A').notifier)
          .loadFile(
            fileName: 'grande.csv',
            bytes: Uint8List(TabularImportSource.maxFileBytes + 1),
          );

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.errorCode, 'fileTooLarge');
      expect(state.errorMessage, contains('2 MB'));
      expect(state.fileBytes, isNull);
      expect(state.actionStatus, CompanyActionStatus.error);
    });

    test('sorgente oltre 500 righe respinta con messaggio dedicato', () async {
      final parser = _FakeParser(
        _source(
          dataRows: [
            for (var i = 0; i < TabularImportSource.maxDataRows + 1; i++)
              ['2026-03-04', 'Movimento $i', '10.00'],
          ],
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      await container
          .read(transactionImportControllerProvider('A').notifier)
          .loadFile(fileName: 'molte.csv', bytes: _fileBytes);

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.errorCode, 'tooManyRows');
      expect(state.errorMessage, contains('500'));
      expect(state.source, isNull);
      expect(state.fileBytes, isNull);
    });

    test('errore di formato tradotto in italiano senza dati del file', () async {
      final container = _container(
        repo: _FakeImportRepo(),
        parser: _ThrowingParser(const FormatException('ambiguousDelimiter')),
      );
      addTearDown(container.dispose);

      await container
          .read(transactionImportControllerProvider('A').notifier)
          .loadFile(fileName: 'movimenti.csv', bytes: _fileBytes);

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.errorCode, 'ambiguousDelimiter');
      expect(state.errorMessage, contains('ambiguo'));
      expect(state.errorMessage, isNot(contains('@')));
      expect(state.errorMessage!.toLowerCase(), isNot(contains('payload')));
    });

    test('errore inatteso del parser non espone dettagli tecnici', () async {
      final container = _container(
        repo: _FakeImportRepo(),
        parser: _ThrowingParser(StateError('stack interno con dati sensibili')),
      );
      addTearDown(container.dispose);

      await container
          .read(transactionImportControllerProvider('A').notifier)
          .loadFile(fileName: 'movimenti.csv', bytes: _fileBytes);

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.errorCode, 'parseFailed');
      expect(state.errorMessage, 'Lettura del file non riuscita.');
      expect(state.errorMessage, isNot(contains('sensibili')));
    });
  });

  group('TransactionImportController mapping e analisi', () {
    test('mapping incompleto blocca l analisi con messaggio dedicato', () async {
      final parser = _FakeParser(
        _source(
          headers: const ['Colonna A', 'Colonna B'],
          dataRows: [
            ['x', 'y'],
          ],
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      final controller = container.read(
        transactionImportControllerProvider('A').notifier,
      );
      await controller.loadFile(fileName: 'movimenti.csv', bytes: _fileBytes);
      await controller.buildPlan();

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.mapping);
      expect(state.errorCode, 'dateMustBeMappedOnce');
      expect(state.errorMessage, contains('Data'));
      expect(state.plan, isNull);
    });

    test('modificare il mapping invalida il piano già calcolato', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      expect(
        container.read(transactionImportControllerProvider('A')).plan,
        isNotNull,
      );

      controller.updateMapping(2, TransactionImportField.ignore);
      expect(
        container.read(transactionImportControllerProvider('A')).plan,
        isNull,
      );
    });

    test('analisi valida porta all anteprima con i conteggi', () async {
      final parser = _FakeParser(
        _source(
          dataRows: [
            ['2026-03-04', 'Incasso cliente', '1500.00'],
            ['2026-03-05', 'Affitto', '-800.00'],
            [null, 'Senza data', '10.00'],
            [null, null, null],
          ],
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      await _prepareToConfirm(container, 'A');

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.preview);
      final plan = state.plan!;
      expect(plan.total, 3);
      expect(plan.valid, 2);
      expect(plan.invalid, 1);
      expect(plan.emptyIgnored, 1);
      expect(plan.selectedForImport, 2);
    });

    test('i movimenti esistenti marcano i possibili duplicati', () async {
      final container = _container(
        repo: _FakeImportRepo(),
        existing: [_existingTransaction()],
      );
      addTearDown(container.dispose);

      await _prepareToConfirm(container, 'A');

      final plan = container
          .read(transactionImportControllerProvider('A'))
          .plan!;
      expect(plan.possibleDuplicate, 1);
      expect(plan.selectedForImport, 0);
    });

    test('errore di caricamento dei movimenti esistenti è recuperabile', () async {
      final container = _container(
        repo: _FakeImportRepo(),
        existingOverride: transactionImportExistingTransactionsProvider
            .overrideWith(
              (ref, companyId) async =>
                  throw StateError('rete non disponibile'),
            ),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        transactionImportControllerProvider('A').notifier,
      );
      await controller.loadFile(fileName: 'movimenti.csv', bytes: _fileBytes);
      await controller.buildPlan();

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.errorCode, 'planFailed');
      expect(state.errorMessage, isNot(contains('rete non disponibile')));
      expect(state.isBusy, isFalse);
    });
  });

  group('TransactionImportController scelta dei formati', () {
    test('importo ambiguo ferma il flusso sulla scelta del formato', () async {
      final parser = _FakeParser(
        _source(
          dataRows: [
            ['2026-03-04', 'Incasso', '1.234'],
          ],
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');

      var state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.formatConfiguration);
      expect(state.plan!.needsNumberFormatSelection, isTrue);
      expect(state.plan!.hasBlockingIssues, isTrue);

      controller.setNumberFormat(NumberFormatPreference.commaDecimal);

      state = container.read(transactionImportControllerProvider('A'));
      expect(state.numberFormat, NumberFormatPreference.commaDecimal);
      expect(state.step, TransactionImportWizardStep.preview);
      expect(state.plan!.needsNumberFormatSelection, isFalse);
      expect(state.plan!.rowsToImport.single.amount, '1234.00');
    });

    test('data ambigua ferma il flusso sulla scelta del formato', () async {
      final parser = _FakeParser(
        _source(
          dataRows: [
            ['03/04/2026', 'Incasso', '10.00'],
          ],
        ),
      );
      final container = _container(repo: _FakeImportRepo(), parser: parser);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      expect(
        container.read(transactionImportControllerProvider('A')).step,
        TransactionImportWizardStep.formatConfiguration,
      );

      controller.setDateFormat(DateFormatPreference.dmy);

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.preview);
      expect(state.plan!.rowsToImport.single.occurredOn, '2026-04-03');
    });

    test('ricalcolo dei formati non interroga di nuovo i movimenti', () async {
      var existingBuilds = 0;
      final parser = _FakeParser(
        _source(
          dataRows: [
            ['2026-03-04', 'Incasso', '1.234'],
          ],
        ),
      );
      final container = _container(
        repo: _FakeImportRepo(),
        parser: parser,
        existingOverride: transactionImportExistingTransactionsProvider
            .overrideWith((ref, companyId) async {
              existingBuilds += 1;
              return <CashTransaction>[];
            }),
      );
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      final buildsAfterPlan = existingBuilds;

      controller.setNumberFormat(NumberFormatPreference.commaDecimal);
      await Future<void>.delayed(Duration.zero);

      expect(existingBuilds, buildsAfterPlan);
    });
  });

  group('TransactionImportController possibili duplicati', () {
    test('includere una riga la riporta tra quelle da importare', () async {
      final container = _container(
        repo: _FakeImportRepo(),
        existing: [_existingTransaction()],
      );
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      final sourceRow = container
          .read(transactionImportControllerProvider('A'))
          .plan!
          .rows
          .firstWhere(
            (row) =>
                row.status == TransactionImportRowStatus.possibleDuplicate,
          )
          .sourceRow;

      controller.toggleDuplicateRow(sourceRow);

      var state = container.read(transactionImportControllerProvider('A'));
      expect(state.includedDuplicateRows, {sourceRow});
      expect(state.plan!.selectedForImport, 1);
      expect(state.plan!.rowsToImport.single.sourceRow, sourceRow);

      controller.toggleDuplicateRow(sourceRow);

      state = container.read(transactionImportControllerProvider('A'));
      expect(state.includedDuplicateRows, isEmpty);
      expect(state.plan!.selectedForImport, 0);
    });
  });

  group('TransactionImportController conferma importazione', () {
    test('invia nome file, impronta, formato e righe selezionate', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();

      expect(repo.callCount, 1);
      expect(repo.lastCompanyId, 'A');
      expect(repo.lastFileName, 'movimenti.csv');
      expect(
        repo.lastSha256,
        TransactionImportFingerprint.fileFingerprint(_fileBytes),
      );
      expect(repo.lastFormat, 'csv');
      expect(repo.lastRows, hasLength(1));
      expect(repo.lastRows.single.description, 'Incasso cliente');
      expect(repo.lastRows.single.rowFingerprint, hasLength(64));

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.result);
      expect(state.result!.importedCount, 1);
      expect(state.actionStatus, CompanyActionStatus.success);
    });

    test('nessuna riga con company_id o id nel payload', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();

      final json = repo.lastRows.single.toJson();
      expect(json.containsKey('company_id'), isFalse);
      expect(json.containsKey('id'), isFalse);
      expect(json.keys, contains('row_fingerprint'));
    });

    test('successo rimuove i byte del file e la sorgente', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      expect(
        container.read(transactionImportControllerProvider('A')).fileBytes,
        isNotNull,
      );

      await controller.confirmImport();

      final state = container.read(transactionImportControllerProvider('A'));
      expect(state.fileBytes, isNull);
      expect(state.source, isNull);
      expect(state.step, TransactionImportWizardStep.result);
    });

    test('successo invalida soltanto i movimenti dell azienda importata', () async {
      final repo = _FakeImportRepo();
      var buildsA = 0;
      var buildsB = 0;

      final container = ProviderContainer(
        overrides: [
          transactionImportFileParserProvider.overrideWithValue(
            _FakeParser(_source()),
          ),
          transactionImportRepositoryProvider.overrideWithValue(repo),
          importTransactionsUseCaseProvider.overrideWithValue(
            ImportTransactions(repo),
          ),
          transactionImportExistingTransactionsProvider.overrideWith(
            (ref, companyId) async => <CashTransaction>[],
          ),
          transactionsProvider.overrideWith((ref, companyId) async {
            if (companyId == 'A') {
              buildsA += 1;
            } else if (companyId == 'B') {
              buildsB += 1;
            }
            return <CashTransaction>[];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(transactionsProvider('A').future);
      await container.read(transactionsProvider('B').future);
      final beforeA = buildsA;
      final beforeB = buildsB;

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();
      await container.read(transactionsProvider('A').future);

      expect(buildsA, greaterThan(beforeA));
      expect(buildsB, beforeB);
    });

    test('doppio tocco su Conferma produce una sola chiamata RPC', () async {
      final gate = Completer<Result<TransactionImportResult>>();
      final repo = _FakeImportRepo(gate: gate);
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      final first = controller.confirmImport();
      await repo.started.future;

      expect(
        container.read(transactionImportControllerProvider('A')).isBusy,
        isTrue,
      );

      await controller.confirmImport();
      expect(repo.callCount, 1);

      gate.complete(Success(_resultWith(importedCount: 1)));
      await first;
      expect(repo.callCount, 1);
    });

    test('loadFile durante l importazione viene ignorato', () async {
      final gate = Completer<Result<TransactionImportResult>>();
      final repo = _FakeImportRepo(gate: gate);
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      final pending = controller.confirmImport();
      await repo.started.future;

      await controller.loadFile(fileName: 'altro.csv', bytes: _fileBytes);
      expect(
        container.read(transactionImportControllerProvider('A')).fileName,
        isNot('altro.csv'),
      );

      gate.complete(Success(_resultWith(importedCount: 1)));
      await pending;
    });

    test('errore RPC torna alla conferma e consente il retry', () async {
      final repo = _FakeImportRepo(
        failure: const AtlasImportFileAlreadyImportedFailure(),
      );
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();

      var state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.confirm);
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.errorCode, 'importFailed');
      expect(state.errorMessage, contains('già stato importato'));
      expect(state.isBusy, isFalse);

      repo.failure = null;
      repo.result = Success(_resultWith(importedCount: 1));
      await controller.confirmImport();

      expect(repo.callCount, 2);
      state = container.read(transactionImportControllerProvider('A'));
      expect(state.step, TransactionImportWizardStep.result);
    });

    test('senza righe da importare la conferma non chiama la RPC', () async {
      final repo = _FakeImportRepo();
      final container = _container(
        repo: repo,
        existing: [_existingTransaction()],
      );
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      expect(
        container
            .read(transactionImportControllerProvider('A'))
            .plan!
            .selectedForImport,
        0,
      );

      await controller.confirmImport();

      expect(repo.callCount, 0);
      expect(
        container.read(transactionImportControllerProvider('A')).errorCode,
        'nothingToImport',
      );
    });

    test('un piano bloccato non viene inviato al server', () async {
      final repo = _FakeImportRepo();
      final parser = _FakeParser(
        _source(
          dataRows: [
            ['2026-03-04', 'Incasso', '1.234'],
          ],
        ),
      );
      final container = _container(repo: repo, parser: parser);
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();

      expect(repo.callCount, 0);
      expect(
        container.read(transactionImportControllerProvider('A')).errorCode,
        'nothingToImport',
      );
    });

    test('risposta tardiva non aggiorna una sessione eliminata', () async {
      final gate = Completer<Result<TransactionImportResult>>();
      final repo = _FakeImportRepo(gate: gate);
      final container = _container(repo: repo);

      final controller = await _prepareToConfirm(container, 'A');
      final pending = controller.confirmImport();
      await repo.started.future;

      container.dispose();
      gate.complete(Success(_resultWith(importedCount: 99)));
      await pending;

      final next = _container(repo: repo);
      addTearDown(next.dispose);
      final state = next.read(transactionImportControllerProvider('A'));
      expect(state.result, isNull);
      expect(state.step, TransactionImportWizardStep.info);
    });

    test('il risultato dell azienda A non appare nell azienda B', () async {
      final container = _container(repo: _FakeImportRepo());
      addTearDown(container.dispose);

      final controller = await _prepareToConfirm(container, 'A');
      await controller.confirmImport();

      expect(
        container.read(transactionImportControllerProvider('A')).result,
        isNotNull,
      );
      expect(
        container.read(transactionImportControllerProvider('B')).result,
        isNull,
      );
    });

    test(
      'commento privacy: i byte diventano eleggibili per la garbage collection, '
      'non è una cancellazione sicura dalla RAM',
      () {
        expect(true, isTrue);
      },
    );
  });
}
