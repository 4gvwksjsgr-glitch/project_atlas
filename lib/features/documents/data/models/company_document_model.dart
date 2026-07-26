import '../../domain/entities/company_document.dart';

class CompanyDocumentModel {
  const CompanyDocumentModel({
    required this.id,
    required this.companyId,
    this.uploadedBy,
    required this.title,
    required this.originalFileName,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? uploadedBy;
  final String title;
  final String originalFileName;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const selectColumns =
      'id, company_id, uploaded_by, title, original_file_name, '
      'storage_path, mime_type, size_bytes, is_archived, created_at, updated_at';

  factory CompanyDocumentModel.fromJson(Map<String, dynamic> json) {
    final sizeRaw = json['size_bytes'];
    final sizeBytes = sizeRaw is int ? sizeRaw : int.parse(sizeRaw.toString());

    return CompanyDocumentModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      uploadedBy: json['uploaded_by'] as String?,
      title: json['title'] as String,
      originalFileName: json['original_file_name'] as String,
      storagePath: json['storage_path'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: sizeBytes,
      isArchived: json['is_archived'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  CompanyDocument toEntity() {
    return CompanyDocument(
      id: id,
      companyId: companyId,
      uploadedBy: uploadedBy,
      title: title,
      originalFileName: originalFileName,
      storagePath: storagePath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      isArchived: isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
