/// Astrazione testabile per aprire URL esterni (signed URL documenti).
abstract class DocumentUrlLauncher {
  Future<bool> canLaunch(String url);
  Future<bool> launch(String url);
}
