class Customer {
  const Customer({
    required this.id,
    required this.companyId,
    required this.name,
    this.email,
    this.phone,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String? email;
  final String? phone;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  String toString() =>
      'Customer(id: $id, companyId: $companyId, createdAt: $createdAt, '
      'updatedAt: $updatedAt)';
}
