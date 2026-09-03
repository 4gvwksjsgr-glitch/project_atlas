import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';

/// Validazione fail-closed dell'URL checkout sandbox Paddle/Pages.
///
/// Host fisso per lo step sandbox 14C-2H: sostituire deliberatamente
/// in un ambiente live futuro.
abstract final class SandboxBillingCheckoutUrl {
  static const expectedHost = 'project-atlas-bxh.pages.dev';
  static const expectedPath = '/billing/checkout';
  static const _ptxnPrefix = 'txn_';
  static const _httpsDefaultPort = 443;

  /// Valida [checkoutUrl] e restituisce l'[Uri] sicuro da aprire.
  static Result<Uri> validate(String checkoutUrl) {
    final trimmed = checkoutUrl.trim();
    if (trimmed.isEmpty) {
      return const Error(AtlasCheckoutInvalidUrlFailure());
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host != expectedHost ||
        !_isAllowedHttpsPort(uri) ||
        uri.path != expectedPath) {
      return const Error(AtlasCheckoutInvalidUrlFailure());
    }

    final ptxnValues = uri.queryParametersAll['_ptxn'];
    if (ptxnValues == null || ptxnValues.length != 1) {
      return const Error(AtlasCheckoutInvalidUrlFailure());
    }

    final ptxn = ptxnValues.single;
    if (!ptxn.startsWith(_ptxnPrefix) || ptxn.length <= _ptxnPrefix.length) {
      return const Error(AtlasCheckoutInvalidUrlFailure());
    }

    return Success(uri);
  }

  /// Accetta assenza di porta esplicita oppure porta 443 (default HTTPS).
  static bool _isAllowedHttpsPort(Uri uri) {
    if (!uri.hasPort) {
      return true;
    }
    return uri.port == _httpsDefaultPort;
  }
}
