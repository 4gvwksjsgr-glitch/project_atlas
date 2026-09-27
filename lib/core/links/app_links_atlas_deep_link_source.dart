import 'package:app_links/app_links.dart';

import 'atlas_deep_link_source.dart';

/// Production [AtlasDeepLinkSource] backed by `app_links`.
class AppLinksAtlasDeepLinkSource implements AtlasDeepLinkSource {
  AppLinksAtlasDeepLinkSource({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialUri() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriStream => _appLinks.uriLinkStream;
}
