import '../../domain/entities/company.dart';

class CompanyModel {
  const CompanyModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Company toEntity() {
    return Company(
      id: id,
      name: name,
      slug: slug,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
