import '../../domain/entities/premium_checkout_session.dart';

class PremiumCheckoutSessionModel {
  const PremiumCheckoutSessionModel({
    required this.schemaVersion,
    required this.checkoutSessionId,
    required this.checkoutUrl,
    required this.returnToken,
    required this.returnTokenVersion,
    required this.expiresAt,
    required this.reused,
  });

  final int schemaVersion;
  final String checkoutSessionId;
  final String checkoutUrl;
  final String returnToken;
  final int returnTokenVersion;
  final DateTime expiresAt;
  final bool reused;

  factory PremiumCheckoutSessionModel.fromJson(Map<String, dynamic> json) {
    final checkoutSessionId = json['checkout_session_id']?.toString();
    final checkoutUrl = json['checkout_url']?.toString();
    final returnToken = json['return_token']?.toString();
    final expiresAtRaw = json['expires_at'];
    final returnTokenVersion = _parseRequiredInt(json['return_token_version']);
    final schemaVersion = _parseRequiredInt(json['schema_version']);
    final reused = json['reused'];

    if (checkoutSessionId == null ||
        checkoutSessionId.isEmpty ||
        checkoutUrl == null ||
        checkoutUrl.isEmpty ||
        returnToken == null ||
        returnToken.isEmpty ||
        returnTokenVersion == null ||
        schemaVersion == null ||
        reused is! bool) {
      throw const FormatException('Payload billing-checkout-create non valido');
    }

    final expiresAt = _parseRequiredDateTime(expiresAtRaw);
    if (expiresAt == null) {
      throw const FormatException('Payload billing-checkout-create non valido');
    }

    return PremiumCheckoutSessionModel(
      schemaVersion: schemaVersion,
      checkoutSessionId: checkoutSessionId,
      checkoutUrl: checkoutUrl,
      returnToken: returnToken,
      returnTokenVersion: returnTokenVersion,
      expiresAt: expiresAt,
      reused: reused,
    );
  }

  PremiumCheckoutSession toEntity() {
    return PremiumCheckoutSession(
      checkoutSessionId: checkoutSessionId,
      checkoutUrl: checkoutUrl,
      returnToken: returnToken,
      returnTokenVersion: returnTokenVersion,
      expiresAt: expiresAt,
      reused: reused,
    );
  }

  static int? _parseRequiredInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value == null) {
      return null;
    }
    return int.tryParse(value.toString());
  }

  static DateTime? _parseRequiredDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
