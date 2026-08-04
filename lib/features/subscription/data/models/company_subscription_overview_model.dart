import '../../domain/entities/company_subscription_overview.dart';

class CompanySubscriptionOverviewModel {
  const CompanySubscriptionOverviewModel({
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
    required this.documentsUsed,
    required this.periodStart,
    required this.periodEnd,
    required this.isUnlimited,
    required this.canActivateTrial,
    required this.entitlementOrigin,
    required this.billingSubscriptionStatus,
    required this.billingPaymentStatus,
    required this.syncStatus,
    required this.lastSyncResult,
    required this.cancelAtPeriodEnd,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.providerAccessStatus,
    required this.providerAccessEndsAt,
    required this.isProviderGrace,
    required this.graceEndsAt,
    required this.hasPaymentIssue,
    required this.billingLinked,
    required this.canOpenBillingPortal,
    required this.billingSyncPending,
  });

  final String companyId;
  final String configuredPlanCode;
  final String configuredPlanName;
  final String status;
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
  final String entitlementOrigin;
  final String billingSubscriptionStatus;
  final String billingPaymentStatus;
  final String syncStatus;
  final String lastSyncResult;
  final bool cancelAtPeriodEnd;
  final DateTime? billingPeriodStart;
  final DateTime? billingPeriodEnd;
  final String providerAccessStatus;
  final DateTime? providerAccessEndsAt;
  final bool isProviderGrace;
  final DateTime? graceEndsAt;
  final bool hasPaymentIssue;
  final bool billingLinked;
  final bool canOpenBillingPortal;
  final bool billingSyncPending;

  factory CompanySubscriptionOverviewModel.fromJson(Map<String, dynamic> json) {
    final companyId = json['company_id']?.toString();
    final configuredPlanCode = json['configured_plan_code']?.toString();
    final configuredPlanName = json['configured_plan_name']?.toString();
    final status = json['subscription_status']?.toString();
    final effectivePlanCode = json['effective_plan_code']?.toString();
    final effectivePlanName = json['effective_plan_name']?.toString();

    if (companyId == null ||
        companyId.isEmpty ||
        configuredPlanCode == null ||
        configuredPlanCode.isEmpty ||
        configuredPlanName == null ||
        configuredPlanName.isEmpty ||
        status == null ||
        status.isEmpty ||
        effectivePlanCode == null ||
        effectivePlanCode.isEmpty ||
        effectivePlanName == null ||
        effectivePlanName.isEmpty) {
      throw const FormatException('Payload subscription overview non valido');
    }

    final documentMonthlyLimit = _parseNullableInt(
      json['document_monthly_limit'],
    );

    final hasIsUnlimitedKey = json.containsKey('is_unlimited');
    final isUnlimited = hasIsUnlimitedKey
        ? json['is_unlimited'] == true
        : documentMonthlyLimit == null;

    return CompanySubscriptionOverviewModel(
      companyId: companyId,
      configuredPlanCode: configuredPlanCode,
      configuredPlanName: configuredPlanName,
      status: status,
      effectivePlanCode: effectivePlanCode,
      effectivePlanName: effectivePlanName,
      documentMonthlyLimit: documentMonthlyLimit,
      trialStartedAt: _parseNullableDateTime(json['trial_started_at']),
      trialEndsAt: _parseNullableDateTime(json['trial_ends_at']),
      trialUsedAt: _parseNullableDateTime(json['trial_used_at']),
      isTrialActive: json['is_trial_active'] == true,
      documentsUsed: _parseInt(json['documents_used'], fallback: 0),
      periodStart: _parseNullableDateTime(json['period_start']),
      periodEnd: _parseNullableDateTime(json['period_end']),
      isUnlimited: isUnlimited,
      canActivateTrial: json['can_activate_trial'] == true,
      entitlementOrigin: json['entitlement_origin']?.toString() ?? 'none',
      billingSubscriptionStatus:
          json['billing_subscription_status']?.toString() ?? 'none',
      billingPaymentStatus: json['billing_payment_status']?.toString() ?? 'none',
      syncStatus: json['sync_status']?.toString() ?? 'idle',
      lastSyncResult: json['last_sync_result']?.toString() ?? 'none',
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      billingPeriodStart: _parseNullableDateTime(json['billing_period_start']),
      billingPeriodEnd: _parseNullableDateTime(json['billing_period_end']),
      providerAccessStatus:
          json['provider_access_status']?.toString() ?? 'none',
      providerAccessEndsAt: _parseNullableDateTime(
        json['provider_access_ends_at'],
      ),
      isProviderGrace: json['is_provider_grace'] == true,
      graceEndsAt: _parseNullableDateTime(json['grace_ends_at']),
      hasPaymentIssue: json['has_payment_issue'] == true,
      billingLinked: json['billing_linked'] == true,
      canOpenBillingPortal: json['can_open_billing_portal'] == true,
      billingSyncPending: json['billing_sync_pending'] == true,
    );
  }

  CompanySubscriptionOverview toEntity() {
    return CompanySubscriptionOverview(
      companyId: companyId,
      configuredPlanCode: configuredPlanCode,
      configuredPlanName: configuredPlanName,
      status: SubscriptionStatus.fromDb(status),
      effectivePlanCode: effectivePlanCode,
      effectivePlanName: effectivePlanName,
      documentMonthlyLimit: documentMonthlyLimit,
      trialStartedAt: trialStartedAt,
      trialEndsAt: trialEndsAt,
      trialUsedAt: trialUsedAt,
      isTrialActive: isTrialActive,
      documentsUsed: documentsUsed,
      periodStart: periodStart,
      periodEnd: periodEnd,
      isUnlimited: isUnlimited,
      canActivateTrial: canActivateTrial,
      entitlementOrigin: EntitlementOrigin.fromDb(entitlementOrigin),
      billingSubscriptionStatus: BillingSubscriptionStatus.fromDb(
        billingSubscriptionStatus,
      ),
      billingPaymentStatus: BillingPaymentStatus.fromDb(billingPaymentStatus),
      syncStatus: BillingSyncStatus.fromDb(syncStatus),
      lastSyncResult: BillingLastSyncResult.fromDb(lastSyncResult),
      cancelAtPeriodEnd: cancelAtPeriodEnd,
      billingPeriodStart: billingPeriodStart,
      billingPeriodEnd: billingPeriodEnd,
      providerAccessStatus: ProviderAccessStatus.fromDb(providerAccessStatus),
      providerAccessEndsAt: providerAccessEndsAt,
      isProviderGrace: isProviderGrace,
      graceEndsAt: graceEndsAt,
      hasPaymentIssue: hasPaymentIssue,
      billingLinked: billingLinked,
      canOpenBillingPortal: canOpenBillingPortal,
      billingSyncPending: billingSyncPending,
    );
  }

  static int _parseInt(Object? value, {required int fallback}) {
    if (value == null) {
      return fallback;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? fallback;
  }

  static int? _parseNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static DateTime? _parseNullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
