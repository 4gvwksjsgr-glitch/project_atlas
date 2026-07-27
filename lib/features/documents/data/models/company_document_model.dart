import '../../domain/entities/company_document.dart';
import '../../domain/entities/document_link_summaries.dart';

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
    this.clientId,
    this.transactionId,
    this.clientSummary,
    this.transactionSummary,
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
  final String? clientId;
  final String? transactionId;
  final DocumentClientSummary? clientSummary;
  final DocumentTransactionSummary? transactionSummary;

  static const selectColumns =
      'id, company_id, uploaded_by, title, original_file_name, '
      'storage_path, mime_type, size_bytes, is_archived, created_at, updated_at, '
      'client_id, transaction_id, '
      'clients!documents_company_client_fkey(id, name), '
      'transactions!documents_company_transaction_fkey('
      'id, description, amount, occurred_on, kind'
      ')';

  factory CompanyDocumentModel.fromJson(Map<String, dynamic> json) {
    final sizeRaw = json['size_bytes'];
    final sizeBytes = sizeRaw is int ? sizeRaw : int.parse(sizeRaw.toString());

    final clientEmbed = _asSingleEmbed(json['clients']);
    final transactionEmbed = _asSingleEmbed(json['transactions']);

    DocumentClientSummary? clientSummary;
    if (clientEmbed != null) {
      clientSummary = DocumentClientSummary(
        id: clientEmbed['id'] as String,
        name: clientEmbed['name'] as String,
      );
    }

    DocumentTransactionSummary? transactionSummary;
    if (transactionEmbed != null) {
      transactionSummary = DocumentTransactionSummary(
        id: transactionEmbed['id'] as String,
        description: transactionEmbed['description'] as String,
        amountCents: _parseAmountCents(transactionEmbed['amount']),
        occurredOn: _parseDateOnly(transactionEmbed['occurred_on']),
        kind: DocumentTransactionKind.fromDbValue(
          transactionEmbed['kind'] as String,
        ),
      );
    }

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
      clientId: json['client_id'] as String?,
      transactionId: json['transaction_id'] as String?,
      clientSummary: clientSummary,
      transactionSummary: transactionSummary,
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
      clientId: clientId,
      transactionId: transactionId,
      clientSummary: clientSummary,
      transactionSummary: transactionSummary,
    );
  }

  static Map<String, dynamic>? _asSingleEmbed(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is List) {
      if (raw.isEmpty) {
        return null;
      }
      final first = raw.first;
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }
    return null;
  }

  static int _parseAmountCents(dynamic raw) {
    final amountString = raw is String ? raw : raw.toString();
    final normalized = amountString.replaceAll(',', '.');
    final parts = normalized.split('.');
    final whole = int.parse(parts[0]);
    final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    return whole * 100 + int.parse(fraction.substring(0, 2));
  }

  static DateTime _parseDateOnly(dynamic raw) {
    final text = raw is String ? raw : raw.toString();
    final datePart = text.contains('T') ? text.split('T').first : text;
    final parts = datePart.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
