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
  static const insufficientPrivileges = 'ATLAS_INSUFFICIENT_PRIVILEGES';
  static const importFileAlreadyImported = 'ATLAS_IMPORT_FILE_ALREADY_IMPORTED';
  static const importPayloadInvalid = 'ATLAS_IMPORT_PAYLOAD_INVALID';
  static const importTooManyRows = 'ATLAS_IMPORT_TOO_MANY_ROWS';
  static const importInProgress = 'ATLAS_IMPORT_IN_PROGRESS';
  static const referralCodeInvalid = 'ATLAS_REFERRAL_CODE_INVALID';
  static const referralClaimWindowClosed = 'ATLAS_REFERRAL_CLAIM_WINDOW_CLOSED';
  static const referralSelfDenied = 'ATLAS_REFERRAL_SELF_DENIED';
  static const referralCodeGenerateFailed =
      'ATLAS_REFERRAL_CODE_GENERATE_FAILED';
  static const referralRedemptionDisabled =
      'ATLAS_REFERRAL_REDEMPTION_DISABLED';
  static const referralNoPendingRewards = 'ATLAS_REFERRAL_NO_PENDING_REWARDS';
  static const referralProviderUnlinked = 'ATLAS_REFERRAL_PROVIDER_UNLINKED';
  static const referralProviderNotActive =
      'ATLAS_REFERRAL_PROVIDER_NOT_ACTIVE';
  static const referralProviderPastDue = 'ATLAS_REFERRAL_PROVIDER_PAST_DUE';
  static const referralProviderTrialing = 'ATLAS_REFERRAL_PROVIDER_TRIALING';
  static const referralProviderCanceled = 'ATLAS_REFERRAL_PROVIDER_CANCELED';
  static const referralScheduledCancel = 'ATLAS_REFERRAL_SCHEDULED_CANCEL';
  static const referralNearRenewal = 'ATLAS_REFERRAL_NEAR_RENEWAL';
  static const referralPreviewNotSafe = 'ATLAS_REFERRAL_PREVIEW_NOT_SAFE';
  static const referralProviderTimeoutUnknown =
      'ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN';
  static const referralProviderRejected = 'ATLAS_REFERRAL_PROVIDER_REJECTED';
  static const referralProviderNotApplied =
      'ATLAS_REFERRAL_PROVIDER_NOT_APPLIED';
  static const referralProviderSubscriptionChanged =
      'ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED';
  static const referralProviderStateConflict =
      'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT';
  static const referralReconcileRequired = 'ATLAS_REFERRAL_RECONCILE_REQUIRED';

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
    insufficientPrivileges,
    importFileAlreadyImported,
    importPayloadInvalid,
    importTooManyRows,
    importInProgress,
    referralCodeInvalid,
    referralClaimWindowClosed,
    referralSelfDenied,
    referralCodeGenerateFailed,
    referralRedemptionDisabled,
    referralNoPendingRewards,
    referralProviderUnlinked,
    referralProviderNotActive,
    referralProviderPastDue,
    referralProviderTrialing,
    referralProviderCanceled,
    referralScheduledCancel,
    referralNearRenewal,
    referralPreviewNotSafe,
    referralProviderTimeoutUnknown,
    referralProviderRejected,
    referralProviderNotApplied,
    referralProviderSubscriptionChanged,
    referralProviderStateConflict,
    referralReconcileRequired,
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
