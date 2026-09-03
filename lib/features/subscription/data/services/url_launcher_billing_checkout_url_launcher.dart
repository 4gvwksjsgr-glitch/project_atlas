import 'package:url_launcher/url_launcher.dart' as ul;

import '../../domain/services/billing_checkout_url_launcher.dart';

class UrlLauncherBillingCheckoutUrlLauncher
    implements BillingCheckoutUrlLauncher {
  @override
  Future<bool> launch(Uri uri) {
    return ul.launchUrl(uri, mode: ul.LaunchMode.externalApplication);
  }
}
