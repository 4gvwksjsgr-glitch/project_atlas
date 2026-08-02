import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Codici applicativi Atlas restituiti dal database (MESSAGE / DETAIL).
abstract final class AtlasErrorCodes {
  static const documentQuotaExceeded = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED';
  static const subscriptionNotFound = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  static const planNotFound = 'ATLAS_PLAN_NOT_FOUND';
  static const companyIdRequired = 'ATLAS_COMPANY_ID_REQUIRED';
  static const notAuthenticated = 'ATLAS_NOT_AUTHENTICATED';
  static const notCompanyMember = 'ATLAS_NOT_COMPANY_MEMBER';
  static const notCompanyOwner = 'ATLAS_NOT_COMPANY_OWNER';
  static const trialAlreadyActive = 'ATLAS_TRIAL_ALREADY_ACTIVE';
  static const alreadyPremium = 'ATLAS_ALREADY_PREMIUM';
  static const trialAlreadyUsed = 'ATLAS_TRIAL_ALREADY_USED';
  static const premiumUnavailable = 'ATLAS_PREMIUM_UNAVAILABLE';

  static const Set<String> all = {
    documentQuotaExceeded,
    subscriptionNotFound,
    planNotFound,
    companyIdRequired,
    notAuthenticated,
    notCompanyMember,
    notCompanyOwner,
    trialAlreadyActive,
    alreadyPremium,
    trialAlreadyUsed,
    premiumUnavailable,
  };

  /// Estrae il primo codice `ATLAS_*` noto da eccezione PostgREST o testo.
  static String? extract(Object error) {
    if (error is supabase.PostgrestException) {
      final fromFields = _findInText(
        [
          error.message,
          error.details?.toString(),
          error.hint,
          error.code,
        ].whereType<String>(),
      );
      if (fromFields != null) {
        return fromFields;
      }
    }

    return _findInText([error.toString()]);
  }

  static bool isCode(Object error, String code) => extract(error) == code;

  static String? _findInText(Iterable<String> parts) {
    for (final part in parts) {
      final upper = part.toUpperCase();
      for (final code in all) {
        if (upper.contains(code)) {
          return code;
        }
      }
    }
    return null;
  }
}
