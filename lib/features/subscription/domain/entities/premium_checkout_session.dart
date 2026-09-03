/// Esito riuscito di `billing-checkout-create`.
class PremiumCheckoutSession {
  const PremiumCheckoutSession({
    required this.checkoutSessionId,
    required this.checkoutUrl,
    required this.returnToken,
    required this.returnTokenVersion,
    required this.expiresAt,
    required this.reused,
  });

  final String checkoutSessionId;
  final String checkoutUrl;
  final String returnToken;
  final int returnTokenVersion;
  final DateTime expiresAt;
  final bool reused;
}
