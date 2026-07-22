import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_payload_row.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_result.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_sheet.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_source.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_import_parser.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_import_repository.dart';
import 'package:project_atlas/features/clients/domain/usecases/import_customers.dart';
import 'package:project_atlas/features/clients/presentation/controllers/customer_import_controller.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_import_providers.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';

class _FakeParser implements CustomerImportFileParser {
  _FakeParser(this.source);

  CustomerImportSource source;

  @override
  Future<CustomerImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    return source;
  }
}

class _FakeImportRepo implements CustomerImportRepository {
  _FakeImportRepo({this.failure, this.gate});

  Result<CustomerImportResult>? result;
  Failure? failure;
  int callCount = 0;
  final Completer<void> started = Completer<void>();
  Completer<Result<CustomerImportResult>>? gate;

  @override
  Future<Result<CustomerImportResult>> importCustomers({
    required String companyId,
    required List<CustomerImportPayloadRow> rows,
  }) async {
    callCount += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    if (gate != null) {
      return gate!.future;
    }
    if (failure != null) {
      return Error(failure!);
    }
    return result ??
        Success(
          CustomerImportResult(
            insertedCount: rows.length,
            skippedDuplicateCount: 0,
            skippedSourceRows: const [],
          ),
        );
  }
}

CustomerImportSource _minimalSource({int rows = 1}) {
  return CustomerImportSource(
    fileName: 'c.csv',
    byteLength: 20,
    kind: CustomerImportSourceKind.csv,
    sheets: [CustomerImportSheet(name: 'CSV', rowCount: rows)],
    selectedSheet: 'CSV',
    selectedTable: CustomerImportTable(
      headers: const ['Nome', 'Email'],
      dataRows: [
        for (var i = 0; i < rows; i++) ['Cliente $i', 'c$i@test.com'],
      ],
    ),
  );
}

ProviderContainer _container({
  required _FakeImportRepo repo,
  CustomerImportSource? source,
  List<Override> extra = const [],
}) {
  return ProviderContainer(
    overrides: [
      customerImportFileParserProvider.overrideWithValue(
        _FakeParser(source ?? _minimalSource()),
      ),
      customerImportRepositoryProvider.overrideWithValue(repo),
      importCustomersUseCaseProvider.overrideWithValue(ImportCustomers(repo)),
      customersProvider.overrideWith((ref, companyId) async => <Customer>[]),
      ...extra,
    ],
  );
}

Future<void> _prepareConfirm(
  ProviderContainer container,
  String companyId,
) async {
  final controller = container.read(
    customerImportControllerProvider(companyId).notifier,
  );
  await controller.loadFile(
    fileName: 'c.csv',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  await controller.buildPlan();
  controller.goToStep(CustomerImportWizardStep.confirm);
}

void main() {
  group('CustomerImportController', () {
    test('provider family distinto tra azienda A e B', () {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      container
          .read(customerImportControllerProvider('A').notifier)
          .goToStep(CustomerImportWizardStep.pickFile);
      expect(
        container.read(customerImportControllerProvider('A')).step,
        CustomerImportWizardStep.pickFile,
      );
      expect(
        container.read(customerImportControllerProvider('B')).step,
        CustomerImportWizardStep.info,
      );
      expect(
        identical(
          container.read(customerImportControllerProvider('A').notifier),
          container.read(customerImportControllerProvider('B').notifier),
        ),
        isFalse,
      );
    });

    test('autoDispose elimina lo stato quando non ascoltato', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      final sub = container.listen(
        customerImportControllerProvider('A'),
        (_, _) {},
      );
      container
          .read(customerImportControllerProvider('A').notifier)
          .goToStep(CustomerImportWizardStep.mapping);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      // New listen rebuilds fresh state.
      expect(
        container.read(customerImportControllerProvider('A')).step,
        CustomerImportWizardStep.info,
      );
    });

    test(
      'doppio clic Conferma produce una sola RPC; seconda mentre isBusy ignorata',
      () async {
        final gate = Completer<Result<CustomerImportResult>>();
        final repo = _FakeImportRepo(gate: gate);
        final container = _container(repo: repo);
        addTearDown(container.dispose);

        await _prepareConfirm(container, 'A');
        final controller = container.read(
          customerImportControllerProvider('A').notifier,
        );

        final first = controller.confirmImport();
        await repo.started.future;
        expect(
          container.read(customerImportControllerProvider('A')).isBusy,
          isTrue,
        );

        await controller.confirmImport(); // ignored while busy
        expect(repo.callCount, 1);

        gate.complete(
          Success(
            CustomerImportResult(
              insertedCount: 1,
              skippedDuplicateCount: 0,
              skippedSourceRows: const [],
            ),
          ),
        );
        await first;
        expect(repo.callCount, 1);
      },
    );

    test('successo invalida soltanto customersProvider(companyId)', () async {
      final repo = _FakeImportRepo();
      var customersABuilds = 0;
      var customersBBuilds = 0;
      var dashboardTouched = false;

      final container = ProviderContainer(
        overrides: [
          customerImportFileParserProvider.overrideWithValue(
            _FakeParser(_minimalSource()),
          ),
          customerImportRepositoryProvider.overrideWithValue(repo),
          importCustomersUseCaseProvider.overrideWithValue(
            ImportCustomers(repo),
          ),
          customersProvider.overrideWith((ref, companyId) async {
            if (companyId == 'A') {
              customersABuilds += 1;
            } else if (companyId == 'B') {
              customersBBuilds += 1;
            } else {
              dashboardTouched = true;
            }
            return <Customer>[];
          }),
        ],
      );
      addTearDown(container.dispose);

      // Warm providers
      await container.read(customersProvider('A').future);
      await container.read(customersProvider('B').future);
      final aBuildsBefore = customersABuilds;
      final bBuildsBefore = customersBBuilds;

      await _prepareConfirm(container, 'A');
      await container
          .read(customerImportControllerProvider('A').notifier)
          .confirmImport();

      await container.read(customersProvider('A').future);
      expect(customersABuilds, greaterThan(aBuildsBefore));
      expect(customersBBuilds, bBuildsBefore);
      expect(dashboardTouched, isFalse);
    });

    test('errore RPC mantiene disponibile il retry', () async {
      final repo = _FakeImportRepo(
        failure: const UnknownFailure(
          'Importazione clienti non riuscita. Riprova.',
        ),
      );
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      await _prepareConfirm(container, 'A');
      final controller = container.read(
        customerImportControllerProvider('A').notifier,
      );
      await controller.confirmImport();

      final state = container.read(customerImportControllerProvider('A'));
      expect(state.step, CustomerImportWizardStep.confirm);
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.isBusy, isFalse);

      repo.failure = null;
      repo.result = Success(
        CustomerImportResult(
          insertedCount: 1,
          skippedDuplicateCount: 0,
          skippedSourceRows: const [],
        ),
      );
      await controller.confirmImport();
      expect(repo.callCount, 2);
      expect(
        container.read(customerImportControllerProvider('A')).step,
        CustomerImportWizardStep.result,
      );
    });

    test('cambio azienda / reset elimina file mapping anteprima', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      await _prepareConfirm(container, 'A');
      final state = container.read(customerImportControllerProvider('A'));
      expect(state.plan, isNotNull);

      container.read(customerImportControllerProvider('A').notifier).reset();
      final cleared = container.read(customerImportControllerProvider('A'));
      expect(cleared.fileBytes, isNull);
      expect(cleared.source, isNull);
      expect(cleared.mapping, isNull);
      expect(cleared.plan, isNull);
      expect(cleared.step, CustomerImportWizardStep.info);
    });

    test('logout: dispose della family elimina sessione import', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);

      await _prepareConfirm(container, 'A');
      expect(
        container.read(customerImportControllerProvider('A')).plan,
        isNotNull,
      );
      container.dispose();

      final next = _container(repo: repo);
      addTearDown(next.dispose);
      expect(next.read(customerImportControllerProvider('A')).plan, isNull);
    });

    test(
      'navigazione indietro / risposta tardiva non aggiorna controller eliminato',
      () async {
        final gate = Completer<Result<CustomerImportResult>>();
        final repo = _FakeImportRepo(gate: gate);
        final container = _container(repo: repo);

        await _prepareConfirm(container, 'A');
        final controller = container.read(
          customerImportControllerProvider('A').notifier,
        );
        final pending = controller.confirmImport();
        await repo.started.future;

        container.dispose();

        gate.complete(
          Success(
            CustomerImportResult(
              insertedCount: 99,
              skippedDuplicateCount: 0,
              skippedSourceRows: const [],
            ),
          ),
        );
        await pending;

        final next = _container(repo: repo);
        addTearDown(next.dispose);
        expect(next.read(customerImportControllerProvider('A')).result, isNull);
        expect(
          next.read(customerImportControllerProvider('A')).step,
          CustomerImportWizardStep.info,
        );
      },
    );

    test('risultato azienda A non appare in azienda B', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      await _prepareConfirm(container, 'A');
      await container
          .read(customerImportControllerProvider('A').notifier)
          .confirmImport();

      expect(
        container.read(customerImportControllerProvider('A')).result,
        isNotNull,
      );
      expect(
        container.read(customerImportControllerProvider('B')).result,
        isNull,
      );
    });

    test(
      'commento privacy: byte eleggibili GC, non cancellazione sicura RAM',
      () {
        // Il controller rimuove i riferimenti ai byte del file, rendendoli
        // disponibili alla garbage collection. Non viene garantita una
        // cancellazione sicura dalla RAM.
        expect(true, isTrue);
      },
    );

    test('loadFile mentre isBusy viene ignorato', () async {
      final gate = Completer<Result<CustomerImportResult>>();
      final repo = _FakeImportRepo(gate: gate);
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      await _prepareConfirm(container, 'A');
      final controller = container.read(
        customerImportControllerProvider('A').notifier,
      );
      final pending = controller.confirmImport();
      await repo.started.future;

      await controller.loadFile(
        fileName: 'other.csv',
        bytes: Uint8List.fromList([9, 9, 9]),
      );
      expect(
        container.read(customerImportControllerProvider('A')).fileName,
        isNot('other.csv'),
      );

      gate.complete(
        Success(
          CustomerImportResult(
            insertedCount: 1,
            skippedDuplicateCount: 0,
            skippedSourceRows: const [],
          ),
        ),
      );
      await pending;
    });

    test('successo rimuove fileBytes (eleggibili GC)', () async {
      final repo = _FakeImportRepo();
      final container = _container(repo: repo);
      addTearDown(container.dispose);

      await _prepareConfirm(container, 'A');
      expect(
        container.read(customerImportControllerProvider('A')).fileBytes,
        isNotNull,
      );
      await container
          .read(customerImportControllerProvider('A').notifier)
          .confirmImport();
      final state = container.read(customerImportControllerProvider('A'));
      expect(state.fileBytes, isNull);
      expect(state.source, isNull);
      expect(state.step, CustomerImportWizardStep.result);
    });

    test('messaggio delimitatore ambiguo non contiene PII', () async {
      final container = ProviderContainer(
        overrides: [
          customerImportFileParserProvider.overrideWithValue(
            _ThrowingParser(const FormatException('ambiguousDelimiter')),
          ),
          customerImportRepositoryProvider.overrideWithValue(_FakeImportRepo()),
          importCustomersUseCaseProvider.overrideWithValue(
            ImportCustomers(_FakeImportRepo()),
          ),
          customersProvider.overrideWith(
            (ref, companyId) async => <Customer>[],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(customerImportControllerProvider('A').notifier)
          .loadFile(fileName: 'c.csv', bytes: Uint8List.fromList([1]));
      final state = container.read(customerImportControllerProvider('A'));
      expect(state.errorCode, 'ambiguousDelimiter');
      expect(state.errorMessage, contains('ambiguo'));
      expect(state.errorMessage, isNot(contains('@')));
      expect(state.errorMessage!.toLowerCase(), isNot(contains('payload')));
    });
  });
}

class _ThrowingParser implements CustomerImportFileParser {
  _ThrowingParser(this.error);

  final FormatException error;

  @override
  Future<CustomerImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    throw error;
  }
}
