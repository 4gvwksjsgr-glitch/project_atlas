import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Codici applicativi Atlas restituiti dal database / Edge Functions.
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
  static const billingLinked = 'ATLAS_BILLING_LINKED';
  static const billingSyncPending = 'ATLAS_BILLING_SYNC_PENDING';
  static const checkoutUnavailable = 'ATLAS_CHECKOUT_UNAVAILABLE';
  static const checkoutNotEligible = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  static const checkoutAlreadyOpen = 'ATLAS_CHECKOUT_ALREADY_OPEN';
  static const checkoutInProgress = 'ATLAS_CHECKOUT_IN_PROGRESS';
  static const checkoutIdempotencyConflict =
      'ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT';
  static const providerOutcomeUnknown = 'ATLAS_PROVIDER_OUTCOME_UNKNOWN';
  static const providerRequestRejected = 'ATLAS_PROVIDER_REQUEST_REJECTED';

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
    billingLinked,
    billingSyncPending,
    checkoutUnavailable,
    checkoutNotEligible,
    checkoutAlreadyOpen,
    checkoutInProgress,
    checkoutIdempotencyConflict,
    providerOutcomeUnknown,
    providerRequestRejected,
  };

  /// Estrae il primo codice `ATLAS_*` noto da eccezione PostgREST,
  /// FunctionException o testo.
  static String? extract(Object error) {
    if (error is supabase.FunctionException) {
      final fromDetails = _extractFromFunctionDetails(error.details);
      if (fromDetails != null) {
        return fromDetails;
      }
      final fromPhrase = error.reasonPhrase;
      if (fromPhrase != null) {
        final fromReason = _findInText([fromPhrase]);
        if (fromReason != null) {
          return fromReason;
        }
      }
    }

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

  static String? _extractFromFunctionDetails(Object? details) {
    if (details is Map) {
      final code = details['error_code']?.toString();
      if (code != null && all.contains(code)) {
        return code;
      }
      return _findInText(details.values.map((e) => e?.toString() ?? ''));
    }
    if (details is String) {
      return _findInText([details]);
    }
    if (details != null) {
      return _findInText([details.toString()]);
    }
    return null;
  }

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
