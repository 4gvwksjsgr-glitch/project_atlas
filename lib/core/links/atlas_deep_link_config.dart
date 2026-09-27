/// Temporary PRE-BETA custom-scheme deep links for Atlas native clients.
///
/// Centralized so the scheme can change before TestFlight without hunting
/// call sites. Universal Links / Associated Domains are intentionally out of
/// scope for PB-2.
abstract final class AtlasDeepLinkConfig {
  static const scheme = 'projectatlas';

  static const authCallbackHost = 'auth';
  static const authCallbackPath = '/callback';

  static const referralHost = 'ref';

  static const billingReturnHost = 'billing';
  static const billingReturnPath = '/return';

  /// Password-reset / auth redirect target for Android & iOS.
  static String get authCallbackUri =>
      '$scheme://$authCallbackHost$authCallbackPath';

  /// Billing return target for native clients (wiring from billing_web deferred).
  static String get billingReturnUri =>
      '$scheme://$billingReturnHost$billingReturnPath';

  static String referralUri(String code) => '$scheme://$referralHost/$code';
}

/// Classified Atlas custom-scheme deep link (fail-closed).
sealed class AtlasDeepLink {
  const AtlasDeepLink();
}

final class AtlasDeepLinkAuthCallback extends AtlasDeepLink {
  const AtlasDeepLinkAuthCallback();
}

final class AtlasDeepLinkReferral extends AtlasDeepLink {
  const AtlasDeepLinkReferral(this.code);

  final String code;
}

final class AtlasDeepLinkBillingReturn extends AtlasDeepLink {
  const AtlasDeepLinkBillingReturn();
}

final class AtlasDeepLinkUnsupported extends AtlasDeepLink {
  const AtlasDeepLinkUnsupported();
}

/// Pure fail-closed parser for PRE-BETA `projectatlas://` links.
abstract final class AtlasDeepLinkParser {
  static AtlasDeepLink parse(Uri? uri) {
    if (uri == null) {
      return const AtlasDeepLinkUnsupported();
    }
    if (uri.scheme != AtlasDeepLinkConfig.scheme) {
      return const AtlasDeepLinkUnsupported();
    }

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    if (host == AtlasDeepLinkConfig.authCallbackHost) {
      if (segments.length == 1 && segments.first == 'callback') {
        return const AtlasDeepLinkAuthCallback();
      }
      return const AtlasDeepLinkUnsupported();
    }

    if (host == AtlasDeepLinkConfig.referralHost) {
      if (segments.length != 1) {
        return const AtlasDeepLinkUnsupported();
      }
      final code = segments.first.trim();
      if (code.isEmpty) {
        return const AtlasDeepLinkUnsupported();
      }
      return AtlasDeepLinkReferral(code);
    }

    if (host == AtlasDeepLinkConfig.billingReturnHost) {
      if (segments.length == 1 && segments.first == 'return') {
        return const AtlasDeepLinkBillingReturn();
      }
      return const AtlasDeepLinkUnsupported();
    }

    return const AtlasDeepLinkUnsupported();
  }

  /// Convenience for string inputs (malformed → unsupported).
  static AtlasDeepLink parseString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const AtlasDeepLinkUnsupported();
    }
    final uri = Uri.tryParse(raw.trim());
    return parse(uri);
  }
}

/// Resolves password-reset `redirectTo` for Web vs native without reading
/// host OS at call sites that need injectable behavior in tests.
String resolvePasswordResetRedirectTo({
  required bool isWeb,
  required String webAppUrl,
}) {
  if (isWeb) {
    return webAppUrl;
  }
  return AtlasDeepLinkConfig.authCallbackUri;
}
