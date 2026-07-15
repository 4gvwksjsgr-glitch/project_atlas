import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/router/go_router_auth_refresh.dart';

void main() {
  group('GoRouterAuthRefresh', () {
    test('scheduleRefresh notifica i listener dopo la microtask', () async {
      final refresh = GoRouterAuthRefresh();
      var notified = false;

      refresh.addListener(() => notified = true);
      refresh.scheduleRefresh();
      refresh.scheduleRefresh();

      expect(notified, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notified, isTrue);
      refresh.dispose();
    });

    test('notifyAuthChanged delega a scheduleRefresh', () async {
      final refresh = GoRouterAuthRefresh();
      var notified = false;

      refresh.addListener(() => notified = true);
      refresh.notifyAuthChanged();

      expect(notified, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notified, isTrue);
      refresh.dispose();
    });
  });
}
