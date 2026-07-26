/// MIME e limiti file per documenti operativi (Step 13A).
abstract final class DocumentFileRules {
  static const maxSizeBytes = 6291456;
  static const maxTitleLength = 160;
  static const maxOriginalFileNameLength = 255;
  static const bucketId = 'company-documents';
  static const signedUrlTtlSeconds = 300;

  static const allowedMimeTypes = <String>{
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  static const allowedExtensions = <String>{
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  static String? canonicalExtensionForMime(String mimeType) {
    return switch (mimeType) {
      'application/pdf' => 'pdf',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };
  }

  static String? mimeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }
}
