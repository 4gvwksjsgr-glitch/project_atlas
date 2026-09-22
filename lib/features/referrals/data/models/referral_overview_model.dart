import '../../domain/entities/referral_link.dart';
import '../../domain/entities/referral_overview.dart';

class ReferralLinkModel {
  const ReferralLinkModel({
    required this.companyId,
    required this.code,
    required this.createdAt,
    required this.rewardedCount,
    required this.maxRewards,
  });

  final String companyId;
  final String code;
  final DateTime createdAt;
  final int rewardedCount;
  final int maxRewards;

  factory ReferralLinkModel.fromJson(Map<String, dynamic> json) {
    final companyId = json['company_id']?.toString();
    final code = json['code']?.toString();
    if (companyId == null ||
        companyId.isEmpty ||
        code == null ||
        code.isEmpty) {
      throw const FormatException('Payload referral link non valido');
    }

    final createdAt = _parseDateTime(json['created_at']);
    if (createdAt == null) {
      throw const FormatException('Payload referral link senza created_at');
    }

    return ReferralLinkModel(
      companyId: companyId,
      code: code,
      createdAt: createdAt,
      rewardedCount: _parseInt(json['rewarded_count'], fallback: 0),
      maxRewards: _parseInt(json['max_rewards'], fallback: 5),
    );
  }

  ReferralLink toEntity() {
    return ReferralLink(
      companyId: companyId,
      code: code,
      createdAt: createdAt,
      rewardedCount: rewardedCount,
      maxRewards: maxRewards,
    );
  }
}

class ClaimReferralResultModel {
  const ClaimReferralResultModel({
    required this.referralId,
    required this.referringCompanyId,
    required this.status,
    required this.claimedAt,
    required this.alreadyClaimed,
  });

  final String referralId;
  final String referringCompanyId;
  final String status;
  final DateTime claimedAt;
  final bool alreadyClaimed;

  factory ClaimReferralResultModel.fromJson(Map<String, dynamic> json) {
    final referralId = json['referral_id']?.toString();
    final referringCompanyId = json['referring_company_id']?.toString();
    final status = json['status']?.toString();
    final claimedAt = _parseDateTime(json['claimed_at']);

    if (referralId == null ||
        referralId.isEmpty ||
        referringCompanyId == null ||
        referringCompanyId.isEmpty ||
        status == null ||
        status.isEmpty ||
        claimedAt == null) {
      throw const FormatException('Payload claim_referral non valido');
    }

    return ClaimReferralResultModel(
      referralId: referralId,
      referringCompanyId: referringCompanyId,
      status: status,
      claimedAt: claimedAt,
      alreadyClaimed: json['already_claimed'] == true,
    );
  }

  ClaimReferralResult toEntity() {
    return ClaimReferralResult(
      referralId: referralId,
      referringCompanyId: referringCompanyId,
      status: status,
      claimedAt: claimedAt,
      alreadyClaimed: alreadyClaimed,
    );
  }
}

class ReferralHistoryItemModel {
  const ReferralHistoryItemModel({
    required this.referralId,
    required this.status,
    required this.claimedAt,
    this.qualifiedAt,
    required this.label,
  });

  final String referralId;
  final String status;
  final DateTime claimedAt;
  final DateTime? qualifiedAt;
  final String label;

  factory ReferralHistoryItemModel.fromJson(Map<String, dynamic> json) {
    final referralId = json['referral_id']?.toString();
    final status = json['status']?.toString();
    final claimedAt = _parseDateTime(json['claimed_at']);
    if (referralId == null ||
        referralId.isEmpty ||
        status == null ||
        status.isEmpty ||
        claimedAt == null) {
      throw const FormatException('Payload referral history item non valido');
    }

    return ReferralHistoryItemModel(
      referralId: referralId,
      status: status,
      claimedAt: claimedAt,
      qualifiedAt: _parseDateTime(json['qualified_at']),
      label: json['label']?.toString() ?? 'friend',
    );
  }

  ReferralHistoryItem toEntity() {
    return ReferralHistoryItem(
      referralId: referralId,
      status: ReferralItemStatus.fromDb(status),
      claimedAt: claimedAt,
      qualifiedAt: qualifiedAt,
      label: label,
    );
  }
}

class ReferralOverviewModel {
  const ReferralOverviewModel({
    required this.companyId,
    this.code,
    required this.rewardedCount,
    required this.maxRewards,
    required this.pendingRedemptionMonths,
    required this.isOwner,
    required this.items,
  });

  final String companyId;
  final String? code;
  final int rewardedCount;
  final int maxRewards;
  final int pendingRedemptionMonths;
  final bool isOwner;
  final List<ReferralHistoryItemModel> items;

  factory ReferralOverviewModel.fromJson(Map<String, dynamic> json) {
    final companyId = json['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const FormatException('Payload referral overview non valido');
    }

    final rawCode = json['code']?.toString();
    final code = (rawCode == null || rawCode.isEmpty) ? null : rawCode;

    return ReferralOverviewModel(
      companyId: companyId,
      code: code,
      rewardedCount: _parseInt(json['rewarded_count'], fallback: 0),
      maxRewards: _parseInt(json['max_rewards'], fallback: 5),
      pendingRedemptionMonths: _parseInt(
        json['pending_redemption_months'],
        fallback: 0,
      ),
      isOwner: json['is_owner'] == true,
      items: _parseItems(json['items']),
    );
  }

  ReferralOverview toEntity() {
    return ReferralOverview(
      companyId: companyId,
      code: code,
      rewardedCount: rewardedCount,
      maxRewards: maxRewards,
      pendingRedemptionMonths: pendingRedemptionMonths,
      isOwner: isOwner,
      items: items.map((item) => item.toEntity()).toList(growable: false),
    );
  }

  static List<ReferralHistoryItemModel> _parseItems(Object? raw) {
    if (raw == null) {
      return const [];
    }
    if (raw is! List) {
      throw const FormatException('Campo items referral non valido');
    }
    return raw.map((entry) {
      if (entry is Map<String, dynamic>) {
        return ReferralHistoryItemModel.fromJson(entry);
      }
      if (entry is Map) {
        return ReferralHistoryItemModel.fromJson(
          Map<String, dynamic>.from(entry),
        );
      }
      throw FormatException('Elemento items referral non valido', entry);
    }).toList(growable: false);
  }
}

int _parseInt(Object? value, {required int fallback}) {
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

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  return DateTime.tryParse(value.toString())?.toUtc();
}
