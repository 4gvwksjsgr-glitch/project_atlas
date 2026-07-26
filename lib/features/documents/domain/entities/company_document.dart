/// Documento operativo aziendale (non fiscale).
class CompanyDocument {
  const CompanyDocument({
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

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage =>
      mimeType == 'image/jpeg' ||
      mimeType == 'image/png' ||
      mimeType == 'image/webp';
}
