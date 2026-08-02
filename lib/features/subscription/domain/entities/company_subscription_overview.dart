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
