import '../../domain/entities/customer.dart';

class CustomerModel {
  const CustomerModel({
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

  static const selectColumns =
      'id, company_id, name, email, phone, notes, created_at, updated_at';

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Customer toEntity() {
    return Customer(
      id: id,
      companyId: companyId,
      name: name,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
