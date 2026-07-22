import '../value_objects/customer_import_field.dart';

class CustomerImportMapping {
  CustomerImportMapping(Map<int, CustomerImportField> fieldsByHeaderIndex)
    : fieldsByHeaderIndex = Map.unmodifiable(fieldsByHeaderIndex);

  final Map<int, CustomerImportField> fieldsByHeaderIndex;

  List<String> get validationCodes {
    final mappedFields = fieldsByHeaderIndex.values
        .where((field) => field != CustomerImportField.ignore)
        .toList();
    final codes = <String>[];

    if (mappedFields
            .where((field) => field == CustomerImportField.name)
            .length !=
        1) {
      codes.add('nameMustBeMappedOnce');
    }

    for (final field in CustomerImportField.values) {
      if (field == CustomerImportField.ignore ||
          field == CustomerImportField.name) {
        continue;
      }
      if (mappedFields.where((mapped) => mapped == field).length > 1) {
        codes.add('fieldMappedMoreThanOnce');
        break;
      }
    }

    return List.unmodifiable(codes);
  }

  bool get isValid => validationCodes.isEmpty;

  CustomerImportField fieldAt(int headerIndex) =>
      fieldsByHeaderIndex[headerIndex] ?? CustomerImportField.ignore;

  @override
  String toString() =>
      'CustomerImportMapping(mappedHeaderCount: ${fieldsByHeaderIndex.length}, '
      'isValid: $isValid)';
}
