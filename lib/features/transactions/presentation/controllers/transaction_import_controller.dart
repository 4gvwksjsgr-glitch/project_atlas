import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tabular_import/tabular_import_source.dart';
import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/entities/transaction_import_mapping.dart';
import '../../domain/entities/transaction_import_plan.dart';
import '../../domain/entities/transaction_import_result.dart';
import '../../domain/entities/transaction_import_source.dart';
import '../../domain/services/transaction_import_fingerprint.dart';
import '../../domain/services/transaction_import_mapper.dart';
import '../../domain/services/transaction_import_validator.dart';
import '../../domain/value_objects/transaction_import_field.dart';
import '../../domain/value_objects/transaction_import_formats.dart';
import '../providers/transaction_import_providers.dart';
import '../providers/transaction_providers.dart';

enum TransactionImportWizardStep {
  info,
  pickFile,
  pickSheet,
  mapping,
  formatConfiguration,
  preview,
  confirm,
  importing,
  result,
}

class TransactionImportControllerState {
  const TransactionImportControllerState({
    this.step = TransactionImportWizardStep.info,
    this.fileName,
    this.fileBytes,
    this.fileSha256,
    this.source,
    this.mapping,
    this.numberFormat = NumberFormatPreference.auto,
    this.dateFormat = DateFormatPreference.auto,
    this.includedDuplicateRows = const {},
    this.plan,
    this.result,
    this.actionStatus = CompanyActionStatus.idle,
    this.errorCode,
    this.errorMessage,
  });

  final TransactionImportWizardStep step;
  final String? fileName;

  /// Byte del file in memoria. Rimossi dopo successo/reset così da diventare
  /// eleggibili per la garbage collection. Non è una cancellazione sicura
  /// dalla RAM.
  final Uint8List? fileBytes;

  /// SHA-256 dei byte originali: resta disponibile dopo la rimozione dei byte.
  final String? fileSha256;

  final TransactionImportSource? source;
  final TransactionImportMapping? mapping;
  final NumberFormatPreference numberFormat;
  final DateFormatPreference dateFormat;

  /// Righe segnalate come possibili duplicati che l'utente vuole importare.
  final Set<int> includedDuplicateRows;

  final TransactionImportPlan? plan;
  final TransactionImportResult? result;
  final CompanyActionStatus actionStatus;
  final String? errorCode;
  final String? errorMessage;

  bool get isBusy =>
      actionStatus == CompanyActionStatus.loading ||
      step == TransactionImportWizardStep.importing;

  /// `csv` / `xlsx` per la RPC di import.
  String? get sourceFormat => switch (source?.kind) {
    TransactionImportSourceKind.csv => 'csv',
    TransactionImportSourceKind.xlsx => 'xlsx',
    null => null,
  };

  TransactionImportControllerState copyWith({
    TransactionImportWizardStep? step,
    String? fileName,
    Uint8List? fileBytes,
    String? fileSha256,
    TransactionImportSource? source,
    TransactionImportMapping? mapping,
    NumberFormatPreference? numberFormat,
    DateFormatPreference? dateFormat,
    Set<int>? includedDuplicateRows,
    TransactionImportPlan? plan,
    TransactionImportResult? result,
    CompanyActionStatus? actionStatus,
    String? errorCode,
    String? errorMessage,
    bool clearFile = false,
    bool clearSource = false,
    bool clearPlan = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return TransactionImportControllerState(
      step: step ?? this.step,
      fileName: clearFile ? null : fileName ?? this.fileName,
      fileBytes: clearFile ? null : fileBytes ?? this.fileBytes,
      fileSha256: clearFile ? null : fileSha256 ?? this.fileSha256,
      source: clearSource ? null : source ?? this.source,
      mapping: clearSource ? null : mapping ?? this.mapping,
      numberFormat: numberFormat ?? this.numberFormat,
      dateFormat: dateFormat ?? this.dateFormat,
      includedDuplicateRows: clearSource
          ? const {}
          : includedDuplicateRows ?? this.includedDuplicateRows,
      plan: clearPlan ? null : plan ?? this.plan,
      result: clearResult ? null : result ?? this.result,
      actionStatus: actionStatus ?? this.actionStatus,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class TransactionImportController
    extends
        AutoDisposeFamilyNotifier<TransactionImportControllerState, String> {
  final _mapper = const TransactionImportMapper();
  final _validator = const TransactionImportValidator();

  /// Chiavi dei movimenti già presenti: rilette a ogni analisi e riusate per
  /// ricalcolare il piano senza interrogare di nuovo il database.
  Set<String> _existingKeys = const {};

  /// Contatore di generazione: una risposta RPC tardiva non deve aggiornare
  /// una sessione eliminata o sostituita. La RPC in volo non viene annullata.
  int _sessionGeneration = 0;
  bool _disposed = false;

  @override
  TransactionImportControllerState build(String companyId) {
    _disposed = false;
    _sessionGeneration += 1;
    _existingKeys = const {};
    // Il controller rimuove i riferimenti ai byte del file, rendendoli
    // disponibili alla garbage collection. Non viene garantita una
    // cancellazione sicura dalla RAM.
    ref.onDispose(() {
      _disposed = true;
      _sessionGeneration += 1;
      _existingKeys = const {};
    });
    return const TransactionImportControllerState();
  }

  void clearError() {
    state = state.copyWith(
      clearError: true,
      actionStatus: CompanyActionStatus.idle,
    );
  }

  void reset() {
    _sessionGeneration += 1;
    _existingKeys = const {};
    state = const TransactionImportControllerState();
  }

  void goToStep(TransactionImportWizardStep step) {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(step: step, clearError: true);
  }

  Future<void> loadFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (state.isBusy) {
      return;
    }

    final generation = _sessionGeneration;
    final companyId = arg;

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearSource: true,
      clearPlan: true,
      clearResult: true,
      fileName: fileName,
      fileBytes: bytes,
      fileSha256: TransactionImportFingerprint.fileFingerprint(bytes),
      numberFormat: NumberFormatPreference.auto,
      dateFormat: DateFormatPreference.auto,
    );

    try {
      if (bytes.lengthInBytes > TabularImportSource.maxFileBytes) {
        if (!_canApply(generation, companyId)) {
          return;
        }
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorCode: 'fileTooLarge',
          errorMessage: 'Il file supera il limite di 2 MB.',
          clearFile: true,
        );
        return;
      }

      final source = await ref
          .read(transactionImportFileParserProvider)
          .parseBytes(fileName: fileName, bytes: bytes);

      if (!_canApply(generation, companyId)) {
        return;
      }

      final blockingCode = source.constraintIssues
          .where(
            (issue) => issue.severity == TabularImportIssueSeverity.error,
          )
          .map((issue) => issue.code)
          .firstOrNull;
      if (blockingCode != null) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorCode: blockingCode,
          errorMessage: messageForFormatCode(blockingCode),
          clearFile: true,
          clearSource: true,
        );
        return;
      }

      final mapping = _mapper.autoMap(source.selectedTable.headers);
      final needsSheetPick =
          source.kind == TransactionImportSourceKind.xlsx &&
          source.sheets.length > 1;

      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        source: source,
        mapping: mapping,
        step: needsSheetPick
            ? TransactionImportWizardStep.pickSheet
            : TransactionImportWizardStep.mapping,
        clearError: true,
      );
    } on FormatException catch (error) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: error.message,
        errorMessage: messageForFormatCode(error.message),
        clearFile: true,
        clearSource: true,
      );
    } catch (_) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'parseFailed',
        errorMessage: 'Lettura del file non riuscita.',
        clearFile: true,
        clearSource: true,
      );
    }
  }

  Future<void> selectSheet(String sheetName) async {
    if (state.isBusy) {
      return;
    }
    final bytes = state.fileBytes;
    final fileName = state.fileName;
    if (bytes == null || fileName == null) {
      return;
    }

    final generation = _sessionGeneration;
    final companyId = arg;

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearPlan: true,
    );

    try {
      final source = await ref
          .read(transactionImportFileParserProvider)
          .parseBytes(
            fileName: fileName,
            bytes: bytes,
            preferredSheet: sheetName,
          );
      if (!_canApply(generation, companyId)) {
        return;
      }

      final blockingCode = source.constraintIssues
          .where(
            (issue) => issue.severity == TabularImportIssueSeverity.error,
          )
          .map((issue) => issue.code)
          .firstOrNull;
      if (blockingCode != null) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorCode: blockingCode,
          errorMessage: messageForFormatCode(blockingCode),
        );
        return;
      }

      final mapping = _mapper.autoMap(source.selectedTable.headers);
      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        source: source,
        mapping: mapping,
        step: TransactionImportWizardStep.mapping,
        clearError: true,
      );
    } on FormatException catch (error) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: error.message,
        errorMessage: messageForFormatCode(error.message),
      );
    } catch (_) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'parseFailed',
        errorMessage: 'Lettura del foglio non riuscita.',
      );
    }
  }

  void updateMapping(int headerIndex, TransactionImportField field) {
    if (state.isBusy || state.mapping == null) {
      return;
    }
    final next = Map<int, TransactionImportField>.from(
      state.mapping!.fieldsByHeaderIndex,
    );
    next[headerIndex] = field;
    state = state.copyWith(
      mapping: TransactionImportMapping(next),
      clearPlan: true,
      clearError: true,
      includedDuplicateRows: const {},
    );
  }

  /// Sceglie il separatore decimale e ricalcola il piano.
  void setNumberFormat(NumberFormatPreference preference) {
    if (state.isBusy || preference == state.numberFormat) {
      return;
    }
    state = state.copyWith(numberFormat: preference, clearError: true);
    _recomputePlan();
  }

  /// Sceglie l'ordine giorno/mese e ricalcola il piano.
  void setDateFormat(DateFormatPreference preference) {
    if (state.isBusy || preference == state.dateFormat) {
      return;
    }
    state = state.copyWith(dateFormat: preference, clearError: true);
    _recomputePlan();
  }

  /// Include o esclude una riga segnalata come possibile duplicato.
  void toggleDuplicateRow(int sourceRow) {
    if (state.isBusy || state.plan == null) {
      return;
    }
    final next = Set<int>.from(state.includedDuplicateRows);
    if (!next.remove(sourceRow)) {
      next.add(sourceRow);
    }
    state = state.copyWith(includedDuplicateRows: next, clearError: true);
    _recomputePlan();
  }

  Future<void> buildPlan() async {
    if (state.isBusy || state.source == null || state.mapping == null) {
      return;
    }

    final mappingCode = state.mapping!.validationCodes.firstOrNull;
    if (mappingCode != null) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: mappingCode,
        errorMessage: messageForMappingCode(mappingCode),
      );
      return;
    }

    final generation = _sessionGeneration;
    final companyId = arg;

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    try {
      final existing = await _loadExistingTransactions();
      if (!_canApply(generation, companyId)) {
        return;
      }
      _existingKeys = TransactionImportValidator.existingMatchKeys(existing);

      final plan = _buildPlanWithCachedKeys();

      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        plan: plan,
        step: _stepForPlan(plan),
        clearError: true,
      );
    } catch (_) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'planFailed',
        errorMessage: 'Analisi del file non riuscita. Riprova.',
      );
    }
  }

  Future<void> confirmImport() async {
    if (state.isBusy) {
      return;
    }
    final plan = state.plan;
    final fileName = state.fileName;
    final fileSha256 = state.fileSha256;
    final sourceFormat = state.sourceFormat;

    if (plan == null ||
        fileName == null ||
        fileSha256 == null ||
        sourceFormat == null ||
        plan.hasBlockingIssues ||
        plan.rowsToImport.isEmpty) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'nothingToImport',
        errorMessage: 'Nessun movimento valido da importare.',
      );
      return;
    }

    final generation = _sessionGeneration;
    final companyId = arg;

    state = state.copyWith(
      step: TransactionImportWizardStep.importing,
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearResult: true,
    );

    try {
      final result = await ref
          .read(importTransactionsUseCaseProvider)
          .call(
            companyId: companyId,
            sourceFileName: fileName,
            sourceFileSha256: fileSha256,
            sourceFormat: sourceFormat,
            rows: plan.rowsToImport,
          );

      // Non annullare la RPC: solo impedire aggiornamenti UI obsoleti.
      if (!_canApply(generation, companyId)) {
        return;
      }

      switch (result) {
        case Success(:final value):
          ref.invalidate(transactionsProvider(companyId));
          ref.invalidate(
            transactionImportExistingTransactionsProvider(companyId),
          );
          state = state.copyWith(
            step: TransactionImportWizardStep.result,
            actionStatus: CompanyActionStatus.success,
            result: value,
            clearFile: true,
            clearSource: true,
            clearError: true,
          );
        case Error(:final failure):
          state = state.copyWith(
            step: TransactionImportWizardStep.confirm,
            actionStatus: CompanyActionStatus.error,
            errorCode: 'importFailed',
            errorMessage: failure.message,
          );
      }
    } catch (_) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        step: TransactionImportWizardStep.confirm,
        actionStatus: CompanyActionStatus.error,
        errorCode: 'importFailed',
        errorMessage: 'Importazione movimenti non riuscita. Riprova.',
      );
    }
  }

  /// Ricalcola il piano sulle chiavi già lette: nessuna nuova query.
  void _recomputePlan() {
    if (state.source == null ||
        state.mapping == null ||
        !state.mapping!.isValid) {
      return;
    }
    final plan = _buildPlanWithCachedKeys();
    state = state.copyWith(
      plan: plan,
      step: _stepForPlan(plan),
      actionStatus: CompanyActionStatus.idle,
    );
  }

  TransactionImportPlan _buildPlanWithCachedKeys() {
    return _validator.buildPlan(
      source: state.source!,
      mapping: state.mapping!,
      numberFormat: state.numberFormat,
      dateFormat: state.dateFormat,
      existingKeys: _existingKeys,
      includedDuplicateRows: state.includedDuplicateRows,
    );
  }

  /// Un file ambiguo si ferma sulla scelta dei formati; la conferma resta
  /// sullo stesso passo finché l'utente non la richiede esplicitamente.
  TransactionImportWizardStep _stepForPlan(TransactionImportPlan plan) {
    if (plan.needsNumberFormatSelection || plan.needsDateFormatSelection) {
      return TransactionImportWizardStep.formatConfiguration;
    }
    if (state.step == TransactionImportWizardStep.confirm) {
      return TransactionImportWizardStep.confirm;
    }
    return TransactionImportWizardStep.preview;
  }

  bool _canApply(int generation, String companyId) {
    return !_disposed && generation == _sessionGeneration && arg == companyId;
  }

  Future<List<CashTransaction>> _loadExistingTransactions() async {
    final provider = transactionImportExistingTransactionsProvider(arg);
    final asyncValue = ref.read(provider);
    if (asyncValue.hasValue) {
      return asyncValue.requireValue;
    }
    return ref.read(provider.future);
  }

  /// Copie italiane per i codici di lettura file: mai codici tecnici in UI.
  static String messageForFormatCode(String code) {
    return switch (code) {
      'fileTooLarge' => 'Il file supera il limite di 2 MB.',
      'unsupportedExtension' => 'Formato non supportato. Usa .csv o .xlsx.',
      'undecodableEncoding' =>
        'Codifica del file non valida. Esporta il CSV in UTF-8 e riprova.',
      'delimiterUndetectable' =>
        'Separatore CSV non riconosciuto (virgola, punto e virgola o tab).',
      'ambiguousDelimiter' =>
        'Separatore CSV ambiguo. Usa un file con struttura non ambigua '
            '(un solo tipo di separatore tra virgola, punto e virgola o tab).',
      'missingHeaders' => 'Intestazioni mancanti.',
      'emptyHeader' => 'Intestazioni vuote non consentite.',
      'duplicateHeaders' => 'Intestazioni duplicate non consentite.',
      'noDataRows' => 'Il file non contiene righe dati.',
      'emptyWorkbook' => 'Il foglio di lavoro è vuoto.',
      'tooManySheets' => 'Troppi fogli Excel (massimo 20).',
      'tooManyRows' => 'Il file supera il limite di 500 righe dati.',
      _ => 'File non valido.',
    };
  }

  /// Copie italiane per i codici di mapping incompleto.
  static String messageForMappingCode(String code) {
    return switch (code) {
      'dateMustBeMappedOnce' =>
        'Associa la colonna Data a una sola colonna del file.',
      'descriptionMustBeMappedOnce' =>
        'Associa la colonna Descrizione a una sola colonna del file.',
      'amountMappingRequired' =>
        'Associa una colonna Importo con segno oppure la coppia Dare e Avere.',
      'fieldMappedMoreThanOnce' =>
        'Ogni campo può essere associato a una sola colonna.',
      _ => 'Associazione delle colonne incompleta.',
    };
  }
}

final transactionImportControllerProvider = NotifierProvider.autoDispose
    .family<
      TransactionImportController,
      TransactionImportControllerState,
      String
    >(TransactionImportController.new);
