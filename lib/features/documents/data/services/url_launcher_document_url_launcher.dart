import 'package:url_launcher/url_launcher.dart' as ul;

import '../../domain/services/document_url_launcher.dart';

class UrlLauncherDocumentUrlLauncher implements DocumentUrlLauncher {
  @override
  Future<bool> canLaunch(String url) {
    return ul.canLaunchUrl(Uri.parse(url));
  }

  @override
  Future<bool> launch(String url) {
    return ul.launchUrl(
      Uri.parse(url),
      mode: ul.LaunchMode.externalApplication,
    );
  }
}
