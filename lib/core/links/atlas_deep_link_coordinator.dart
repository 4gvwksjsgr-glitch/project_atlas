import 'dart:async';

import 'package:flutter/foundation.dart';

import '../router/route_paths.dart';
import 'atlas_deep_link_config.dart';
import 'atlas_deep_link_source.dart';

/// Routes Atlas-owned non-auth custom-scheme links into GoRouter locations.
///
/// Auth callbacks (`projectatlas://auth/callback…`) are classified but not
/// navigated — `supabase_flutter` owns session exchange when
/// `detectSessionInUri` is enabled on native.
class AtlasDeepLinkCoordinator {
  AtlasDeepLinkCoordinator({
    required this.source,
    required this.go,
    required this.enabled,
  });

  final AtlasDeepLinkSource source;
  final void Function(String location) go;

  /// When false (Flutter Web), the coordinator is a no-op.
  final bool enabled;

  final Set<String> _handledKeys = <String>{};
  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  /// Starts cold-start + warm listeners. Idempotent.
  Future<void> start() async {
    if (!enabled || _started) {
      return;
    }
    _started = true;

    final initial = await source.getInitialUri();
    if (initial != null) {
      handleUri(initial);
    }

    _subscription = source.uriStream.listen(handleUri);
  }

  /// Processes one URI (also used by tests). Dedupes identical deliveries.
  void handleUri(Uri uri) {
    if (!enabled) {
      return;
    }

    final key = _dedupeKey(uri);
    if (!_handledKeys.add(key)) {
      return;
    }

    final link = AtlasDeepLinkParser.parse(uri);
    switch (link) {
      case AtlasDeepLinkAuthCallback():
        // Session exchange is owned by supabase_flutter on native.
        return;
      case AtlasDeepLinkReferral(:final code):
        go(RoutePaths.referral(code));
      case AtlasDeepLinkBillingReturn():
        go(RoutePaths.settingsCompany);
      case AtlasDeepLinkUnsupported():
        return;
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @visibleForTesting
  Set<String> get debugHandledKeys => Set.unmodifiable(_handledKeys);

  static String _dedupeKey(Uri uri) {
    // Ignore fragment noise; keep query (auth codes differ by query).
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
}
