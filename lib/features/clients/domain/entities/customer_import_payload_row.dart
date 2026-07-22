class CustomerImportPayloadRow {
  const CustomerImportPayloadRow({
    required this.sourceRow,
    required this.name,
    this.email,
    this.phone,
    this.notes,
  });

  final int sourceRow;
  final String name;
  final String? email;
  final String? phone;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'source_row': sourceRow,
    'name': name,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (notes != null) 'notes': notes,
  };

  @override
  String toString() => 'CustomerImportPayloadRow(sourceRow: $sourceRow)';
}
