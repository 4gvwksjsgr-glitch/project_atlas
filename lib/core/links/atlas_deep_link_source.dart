/// Injectable source of native deep-link URIs (cold start + warm).
abstract interface class AtlasDeepLinkSource {
  Future<Uri?> getInitialUri();

  Stream<Uri> get uriStream;
}
