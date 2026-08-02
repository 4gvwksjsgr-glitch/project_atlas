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
