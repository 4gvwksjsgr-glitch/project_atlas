import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'app_links_atlas_deep_link_source.dart';
import 'atlas_deep_link_coordinator.dart';
import 'atlas_deep_link_source.dart';

final atlasDeepLinkSourceProvider = Provider<AtlasDeepLinkSource>((ref) {
  return AppLinksAtlasDeepLinkSource();
});

/// Starts native deep-link routing once. No-op on Web.
final atlasDeepLinkCoordinatorProvider = Provider<AtlasDeepLinkCoordinator>((
  ref,
) {
  final router = ref.watch(goRouterProvider);
  final source = ref.watch(atlasDeepLinkSourceProvider);
  final coordinator = AtlasDeepLinkCoordinator(
    source: source,
    go: router.go,
    enabled: !kIsWeb,
  );
  // Fire-and-forget; errors surface via app_links / router.
  // ignore: discarded_futures
  coordinator.start();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
