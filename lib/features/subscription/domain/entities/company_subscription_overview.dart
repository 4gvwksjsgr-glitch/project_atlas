enum SubscriptionStatus {
  free,
  trialing,
  active,
  unknown;

  static SubscriptionStatus fromDb(String value) {
    switch (value) {
      case 'free':
        return SubscriptionStatus.free;
      case 'trialing':
        return SubscriptionStatus.trialing;
      case 'active':
        return SubscriptionStatus.active;
      default:
        return SubscriptionStatus.unknown;
    }
  }

  String get dbValue => switch (this) {
    SubscriptionStatus.free => 'free',
    SubscriptionStatus.trialing => 'trialing',
    SubscriptionStatus.active => 'active',
    SubscriptionStatus.unknown => 'unknown',
  };
}

enum EntitlementOrigin {
  none,
  manual,
  internalTrial,
  provider,
  unknown;

  static EntitlementOrigin fromDb(String? value) {
    switch (value) {
      case null:
      case 'none':
        return EntitlementOrigin.none;
      case 'manual':
        return EntitlementOrigin.manual;
      case 'internal_trial':
        return EntitlementOrigin.internalTrial;
      case 'provider':
        return EntitlementOrigin.provider;
      default:
        return EntitlementOrigin.unknown;
    }
  }
}

enum BillingSubscriptionStatus {
  none,
  incomplete,
  active,
  paused,
  ended,
  revoked,
  unknown;

  static BillingSubscriptionStatus fromDb(String? value) {
    switch (value) {
      case null:
      case 'none':
        return BillingSubscriptionStatus.none;
      case 'incomplete':
        return BillingSubscriptionStatus.incomplete;
      case 'active':
        return BillingSubscriptionStatus.active;
      case 'paused':
        return BillingSubscriptionStatus.paused;
      case 'ended':
        return BillingSubscriptionStatus.ended;
      case 'revoked':
        return BillingSubscriptionStatus.revoked;
      default:
        return BillingSubscriptionStatus.unknown;
    }
  }
}

enum BillingPaymentStatus {
  none,
  ok,
  pending,
  failed,
  pastDue,
  refunded,
  unknown;

  static BillingPaymentStatus fromDb(String? value) {
    switch (value) {
      case null:
      case 'none':
        return BillingPaymentStatus.none;
      case 'ok':
        return BillingPaymentStatus.ok;
      case 'pending':
        return BillingPaymentStatus.pending;
      case 'failed':
        return BillingPaymentStatus.failed;
      case 'past_due':
        return BillingPaymentStatus.pastDue;
      case 'refunded':
        return BillingPaymentStatus.refunded;
      default:
        return BillingPaymentStatus.unknown;
    }
  }
}

enum BillingSyncStatus {
  idle,
  pending,
  processing,
  reconcileRequired,
  unknown;

  static BillingSyncStatus fromDb(String? value) {
    switch (value) {
      case null:
      case 'idle':
        return BillingSyncStatus.idle;
      case 'pending':
        return BillingSyncStatus.pending;
      case 'processing':
        return BillingSyncStatus.processing;
      case 'reconcile_required':
        return BillingSyncStatus.reconcileRequired;
      default:
        return BillingSyncStatus.unknown;
    }
  }
}

enum BillingLastSyncResult {
  none,
  succeeded,
  failed,
  unknown;

  static BillingLastSyncResult fromDb(String? value) {
    switch (value) {
      case null:
      case 'none':
        return BillingLastSyncResult.none;
      case 'succeeded':
        return BillingLastSyncResult.succeeded;
      case 'failed':
        return BillingLastSyncResult.failed;
      default:
        return BillingLastSyncResult.unknown;
    }
  }
}

enum ProviderAccessStatus {
  none,
  entitled,
  grace,
  blocked,
  ended,
  unknown;

  static ProviderAccessStatus fromDb(String? value) {
    switch (value) {
      case null:
      case 'none':
        return ProviderAccessStatus.none;
      case 'entitled':
        return ProviderAccessStatus.entitled;
      case 'grace':
        return ProviderAccessStatus.grace;
      case 'blocked':
        return ProviderAccessStatus.blocked;
      case 'ended':
        return ProviderAccessStatus.ended;
      default:
        return ProviderAccessStatus.unknown;
    }
  }
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.code,
    required this.name,
    required this.documentMonthlyLimit,
  });

  final String code;
  final String name;
  final int? documentMonthlyLimit;

  bool get isUnlimited => documentMonthlyLimit == null;
}

class CompanySubscriptionOverview {
  const CompanySubscriptionOverview({
    required this.companyId,
    required this.configuredPlanCode,
    required this.configuredPlanName,
    required this.status,
    required this.effectivePlanCode,
    required this.effectivePlanName,
    required this.documentMonthlyLimit,
    required this.trialStartedAt,
    required this.trialEndsAt,
    required this.trialUsedAt,
    required this.isTrialActive,
    this.documentsUsed = 0,
    this.periodStart,
    this.periodEnd,
    this.isUnlimited = false,
    this.canActivateTrial = false,
    this.entitlementOrigin = EntitlementOrigin.none,
    this.billingSubscriptionStatus = BillingSubscriptionStatus.none,
    this.billingPaymentStatus = BillingPaymentStatus.none,
    this.syncStatus = BillingSyncStatus.idle,
    this.lastSyncResult = BillingLastSyncResult.none,
    this.cancelAtPeriodEnd = false,
    this.billingPeriodStart,
    this.billingPeriodEnd,
    this.providerAccessStatus = ProviderAccessStatus.none,
    this.providerAccessEndsAt,
    this.isProviderGrace = false,
    this.graceEndsAt,
    this.hasPaymentIssue = false,
    this.billingLinked = false,
    this.canOpenBillingPortal = false,
    this.billingSyncPending = false,
    this.isCheckoutEligible = false,
  });

  final String companyId;
  final String configuredPlanCode;
  final String configuredPlanName;
  final SubscriptionStatus status;
  final String effectivePlanCode;
  final String effectivePlanName;
  final int? documentMonthlyLimit;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? trialUsedAt;
  final bool isTrialActive;
  final int documentsUsed;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final bool isUnlimited;
  final bool canActivateTrial;
  final EntitlementOrigin entitlementOrigin;
  final BillingSubscriptionStatus billingSubscriptionStatus;
  final BillingPaymentStatus billingPaymentStatus;
  final BillingSyncStatus syncStatus;
  final BillingLastSyncResult lastSyncResult;
  final bool cancelAtPeriodEnd;
  final DateTime? billingPeriodStart;
  final DateTime? billingPeriodEnd;
  final ProviderAccessStatus providerAccessStatus;
  final DateTime? providerAccessEndsAt;
  final bool isProviderGrace;
  final DateTime? graceEndsAt;
  final bool hasPaymentIssue;
  final bool billingLinked;
  final bool canOpenBillingPortal;
  final bool billingSyncPending;
  final bool isCheckoutEligible;

  bool get isEffectiveUnlimited => isUnlimited;

  bool get isEffectivePremium => effectivePlanCode == 'premium';

  bool get isEffectiveFree => effectivePlanCode == 'free';

  bool get isQuotaExhausted {
    final limit = documentMonthlyLimit;
    if (isUnlimited || limit == null) {
      return false;
    }
    return documentsUsed >= limit;
  }
}
