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

    return CompanySubscriptionOverviewModel(
      companyId: companyId,
      configuredPlanCode: configuredPlanCode,
      configuredPlanName: configuredPlanName,
      status: status,
      effectivePlanCode: effectivePlanCode,
      effectivePlanName: effectivePlanName,
      documentMonthlyLimit: _parseNullableInt(json['document_monthly_limit']),
      trialStartedAt: _parseNullableDateTime(json['trial_started_at']),
      trialEndsAt: _parseNullableDateTime(json['trial_ends_at']),
      trialUsedAt: _parseNullableDateTime(json['trial_used_at']),
      isTrialActive: json['is_trial_active'] == true,
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
    );
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
