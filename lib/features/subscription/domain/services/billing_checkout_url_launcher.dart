/// Astrazione testabile per aprire l'URL HTTPS del checkout in un nuovo tab.
abstract class BillingCheckoutUrlLauncher {
  Future<bool> launch(Uri uri);
}
