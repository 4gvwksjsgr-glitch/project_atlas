import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/links/atlas_deep_link_coordinator.dart';
import 'package:project_atlas/core/links/atlas_deep_link_source.dart';
import 'package:project_atlas/core/router/route_paths.dart';

class _FakeLinkSource implements AtlasDeepLinkSource {
  _FakeLinkSource({this.initial, StreamController<Uri>? controller})
    : _controller = controller ?? StreamController<Uri>.broadcast();

  final Uri? initial;
  final StreamController<Uri> _controller;

  @override
  Future<Uri?> getInitialUri() async => initial;

  @override
  Stream<Uri> get uriStream => _controller.stream;

  void emit(Uri uri) => _controller.add(uri);

  Future<void> close() => _controller.close();
}

void main() {
  group('AtlasDeepLinkCoordinator', () {
    test('referral maps to existing /ref/:code route', () async {
      final routes = <String>[];
      final source = _FakeLinkSource();
      final coordinator = AtlasDeepLinkCoordinator(
        source: source,
        go: routes.add,
        enabled: true,
      );

      coordinator.handleUri(Uri.parse('projectatlas://ref/ABC123'));
      expect(routes, [RoutePaths.referral('ABC123')]);
      await source.close();
      coordinator.dispose();
    });

    test('billing return maps to settings company', () {
      final routes = <String>[];
      final source = _FakeLinkSource();
      final coordinator = AtlasDeepLinkCoordinator(
        source: source,
        go: routes.add,
        enabled: true,
      );

      coordinator.handleUri(Uri.parse('projectatlas://billing/return'));
      expect(routes, [RoutePaths.settingsCompany]);
      coordinator.dispose();
    });

    test('auth callback does not navigate', () {
      final routes = <String>[];
      final source = _FakeLinkSource();
      final coordinator = AtlasDeepLinkCoordinator(
        source: source,
        go: routes.add,
        enabled: true,
      );

      coordinator.handleUri(
        Uri.parse('projectatlas://auth/callback?code=xyz'),
      );
      expect(routes, isEmpty);
      coordinator.dispose();
    });

    test('duplicate delivery does not double-route', () async {
      final routes = <String>[];
      final controller = StreamController<Uri>.broadcast();
      final uri = Uri.parse('projectatlas://ref/DUPCODE');
      final source = _FakeLinkSource(initial: uri, controller: controller);
      final coordinator = AtlasDeepLinkCoordinator(
        source: source,
        go: routes.add,
        enabled: true,
      );

      await coordinator.start();
      source.emit(uri);
      source.emit(uri);
      await Future<void>.delayed(Duration.zero);

      expect(routes, [RoutePaths.referral('DUPCODE')]);
      expect(coordinator.debugHandledKeys.length, 1);

      await source.close();
      coordinator.dispose();
    });

    test('disabled (web) ignores links', () {
      final routes = <String>[];
      final source = _FakeLinkSource();
      final coordinator = AtlasDeepLinkCoordinator(
        source: source,
        go: routes.add,
        enabled: false,
      );

      coordinator.handleUri(Uri.parse('projectatlas://ref/ABC'));
      expect(routes, isEmpty);
      coordinator.dispose();
    });
  });
}
