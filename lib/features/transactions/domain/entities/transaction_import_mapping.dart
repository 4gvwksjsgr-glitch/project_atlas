import '../value_objects/transaction_import_field.dart';

/// Come l'utente vuole leggere l'importo: colonna unica con segno oppure
/// due colonne dare/avere.
enum TransactionImportAmountMode { none, signed, debitCredit }

class TransactionImportMapping {
  TransactionImportMapping(Map<int, TransactionImportField> fieldsByHeaderIndex)
    : fieldsByHeaderIndex = Map.unmodifiable(fieldsByHeaderIndex);

  final Map<int, TransactionImportField> fieldsByHeaderIndex;

  int _countOf(TransactionImportField field) => fieldsByHeaderIndex.values
      .where((mapped) => mapped == field)
      .length;

  TransactionImportAmountMode get amountMode {
    final signed = _countOf(TransactionImportField.signedAmount);
    final debit = _countOf(TransactionImportField.debit);
    final credit = _countOf(TransactionImportField.credit);

    if (signed == 1 && debit == 0 && credit == 0) {
      return TransactionImportAmountMode.signed;
    }
    if (signed == 0 && debit == 1 && credit == 1) {
      return TransactionImportAmountMode.debitCredit;
    }
    return TransactionImportAmountMode.none;
  }

  List<String> get validationCodes {
    final codes = <String>[];

    if (_countOf(TransactionImportField.date) != 1) {
      codes.add('dateMustBeMappedOnce');
    }
    if (_countOf(TransactionImportField.description) != 1) {
      codes.add('descriptionMustBeMappedOnce');
    }
    if (amountMode == TransactionImportAmountMode.none) {
      codes.add('amountMappingRequired');
    }

    for (final field in [
      TransactionImportField.reference,
      TransactionImportField.notes,
    ]) {
      if (_countOf(field) > 1) {
        codes.add('fieldMappedMoreThanOnce');
        break;
      }
    }

    return List.unmodifiable(codes);
  }

  bool get isValid => validationCodes.isEmpty;

  TransactionImportField fieldAt(int headerIndex) =>
      fieldsByHeaderIndex[headerIndex] ?? TransactionImportField.ignore;

  int? headerIndexOf(TransactionImportField field) {
    for (final entry in fieldsByHeaderIndex.entries) {
      if (entry.value == field) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'TransactionImportMapping(mappedHeaderCount: '
      '${fieldsByHeaderIndex.length}, isValid: $isValid)';
}
