import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/customer_import_mapping.dart';
import '../../domain/entities/customer_import_plan.dart';
import '../../domain/entities/customer_import_result.dart';
import '../../domain/entities/customer_import_source.dart';
import '../../domain/services/customer_import_mapper.dart';
import '../../domain/services/customer_import_validator.dart';
import '../../domain/value_objects/customer_import_field.dart';
import '../../domain/value_objects/normalized_email.dart';
import '../providers/customer_import_providers.dart';
import '../providers/customer_providers.dart';

enum CustomerImportWizardStep {
  info,
  pickFile,
  pickSheet,
  mapping,
  preview,
  confirm,
  importing,
  result,
}

class CustomerImportControllerState {
  const CustomerImportControllerState({
    this.step = CustomerImportWizardStep.info,
    this.fileName,
    this.fileBytes,
    this.source,
    this.mapping,
    this.plan,
    this.result,
    this.actionStatus = CompanyActionStatus.idle,
    this.errorCode,
    this.errorMessage,
  });

  final CustomerImportWizardStep step;
  final String? fileName;

  /// In-memory file bytes. Cleared after success/reset so they become eligible
  /// for garbage collection. Not a secure wipe from RAM.
  final Uint8List? fileBytes;
  final CustomerImportSource? source;
  final CustomerImportMapping? mapping;
  final CustomerImportPlan? plan;
  final CustomerImportResult? result;
  final CompanyActionStatus actionStatus;
  final String? errorCode;
  final String? errorMessage;

  bool get isBusy =>
      actionStatus == CompanyActionStatus.loading ||
      step == CustomerImportWizardStep.importing;

  CustomerImportControllerState copyWith({
    CustomerImportWizardStep? step,
    String? fileName,
    Uint8List? fileBytes,
    CustomerImportSource? source,
    CustomerImportMapping? mapping,
    CustomerImportPlan? plan,
    CustomerImportResult? result,
    CompanyActionStatus? actionStatus,
    String? errorCode,
    String? errorMessage,
    bool clearFile = false,
    bool clearSource = false,
    bool clearPlan = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return CustomerImportControllerState(
      step: step ?? this.step,
      fileName: clearFile ? null : fileName ?? this.fileName,
      fileBytes: clearFile ? null : fileBytes ?? this.fileBytes,
      source: clearSource ? null : source ?? this.source,
      mapping: clearSource ? null : mapping ?? this.mapping,
      plan: clearPlan ? null : plan ?? this.plan,
      result: clearResult ? null : result ?? this.result,
      actionStatus: actionStatus ?? this.actionStatus,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class CustomerImportController
    extends AutoDisposeFamilyNotifier<CustomerImportControllerState, String> {
  final _mapper = const CustomerImportMapper();
  final _validator = const CustomerImportValidator();

  /// Generation counter: late RPC responses must not update a disposed or
  /// superseded session. The in-flight RPC is never cancelled.
  int _sessionGeneration = 0;
  bool _disposed = false;

  @override
  CustomerImportControllerState build(String companyId) {
    _disposed = false;
    _sessionGeneration += 1;
    // Il controller rimuove i riferimenti ai byte del file, rendendoli
    // disponibili alla garbage collection. Non viene garantita una
    // cancellazione sicura dalla RAM.
    ref.onDispose(() {
      _disposed = true;
      _sessionGeneration += 1;
    });
    return const CustomerImportControllerState();
  }

  void clearError() {
    state = state.copyWith(
      clearError: true,
      actionStatus: CompanyActionStatus.idle,
    );
  }

  void reset() {
    _sessionGeneration += 1;
    state = const CustomerImportControllerState();
  }

  void goToStep(CustomerImportWizardStep step) {
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
    );

    try {
      if (bytes.lengthInBytes > CustomerImportSource.maxFileBytes) {
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
          .read(customerImportFileParserProvider)
          .parseBytes(fileName: fileName, bytes: bytes);

      if (!_canApply(generation, companyId)) {
        return;
      }

      if (source.constraintIssues.any((i) => i.code == 'tooManyRows')) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorCode: 'tooManyRows',
          errorMessage: 'Il file supera il limite di 500 righe dati.',
          clearFile: true,
          clearSource: true,
        );
        return;
      }

      final mapping = _mapper.autoMap(source.selectedTable.headers);
      final needsSheetPick =
          source.kind == CustomerImportSourceKind.xlsx &&
          source.sheets.length > 1;

      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        source: source,
        mapping: mapping,
        step: needsSheetPick
            ? CustomerImportWizardStep.pickSheet
            : CustomerImportWizardStep.mapping,
        clearError: true,
      );
    } on FormatException catch (error) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: error.message,
        errorMessage: _messageForFormatCode(error.message),
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
          .read(customerImportFileParserProvider)
          .parseBytes(
            fileName: fileName,
            bytes: bytes,
            preferredSheet: sheetName,
          );
      if (!_canApply(generation, companyId)) {
        return;
      }
      final mapping = _mapper.autoMap(source.selectedTable.headers);
      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        source: source,
        mapping: mapping,
        step: CustomerImportWizardStep.mapping,
        clearError: true,
      );
    } on FormatException catch (error) {
      if (!_canApply(generation, companyId)) {
        return;
      }
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: error.message,
        errorMessage: _messageForFormatCode(error.message),
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

  void updateMapping(int headerIndex, CustomerImportField field) {
    if (state.isBusy || state.mapping == null) {
      return;
    }
    final next = Map<int, CustomerImportField>.from(
      state.mapping!.fieldsByHeaderIndex,
    );
    next[headerIndex] = field;
    state = state.copyWith(
      mapping: CustomerImportMapping(next),
      clearPlan: true,
      clearError: true,
    );
  }

  Future<void> buildPlan() async {
    if (state.isBusy || state.source == null || state.mapping == null) {
      return;
    }
    if (!state.mapping!.isValid) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'incompleteMapping',
        errorMessage:
            'Associa obbligatoriamente la colonna Nome o ragione sociale.',
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
      final customers = await _loadCustomers();
      if (!_canApply(generation, companyId)) {
        return;
      }
      final existingEmails = <String>{
        for (final customer in customers)
          if (customer.email != null && customer.email!.trim().isNotEmpty)
            normalizeEmail(customer.email!),
      };

      final plan = _validator.buildPlan(
        source: state.source!,
        mapping: state.mapping!,
        existingEmailsNormalized: existingEmails,
      );

      state = state.copyWith(
        actionStatus: CompanyActionStatus.idle,
        plan: plan,
        step: CustomerImportWizardStep.preview,
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
    if (plan == null || plan.hasBlockingIssues || plan.rowsToImport.isEmpty) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorCode: 'nothingToImport',
        errorMessage: 'Nessun cliente valido da importare.',
      );
      return;
    }

    final generation = _sessionGeneration;
    final companyId = arg;

    state = state.copyWith(
      step: CustomerImportWizardStep.importing,
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearResult: true,
    );

    try {
      final result = await ref
          .read(importCustomersUseCaseProvider)
          .call(companyId: companyId, rows: plan.rowsToImport);

      // Non annullare la RPC: solo impedire aggiornamenti UI obsoleti.
      if (!_canApply(generation, companyId)) {
        return;
      }

      switch (result) {
        case Success(:final value):
          ref.invalidate(customersProvider(companyId));
          state = state.copyWith(
            step: CustomerImportWizardStep.result,
            actionStatus: CompanyActionStatus.success,
            result: value,
            clearFile: true,
            clearSource: true,
            clearError: true,
          );
        case Error(:final failure):
          state = state.copyWith(
            step: CustomerImportWizardStep.confirm,
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
        step: CustomerImportWizardStep.confirm,
        actionStatus: CompanyActionStatus.error,
        errorCode: 'importFailed',
        errorMessage: 'Importazione clienti non riuscita. Riprova.',
      );
    }
  }

  bool _canApply(int generation, String companyId) {
    return !_disposed && generation == _sessionGeneration && arg == companyId;
  }

  Future<List<Customer>> _loadCustomers() async {
    final asyncValue = ref.read(customersProvider(arg));
    if (asyncValue.hasValue) {
      return asyncValue.requireValue;
    }
    return ref.read(customersProvider(arg).future);
  }

  static String _messageForFormatCode(String code) {
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
}

final customerImportControllerProvider = NotifierProvider.autoDispose
    .family<CustomerImportController, CustomerImportControllerState, String>(
      CustomerImportController.new,
    );
