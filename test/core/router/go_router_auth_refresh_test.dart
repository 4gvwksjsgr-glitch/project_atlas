import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/router/go_router_auth_refresh.dart';

void main() {
  group('GoRouterAuthRefresh', () {
    test('notifyAuthChanged notifica i listener', () {
      final refresh = GoRouterAuthRefresh();
      var notified = false;

      refresh.addListener(() => notified = true);
      refresh.notifyAuthChanged();

      expect(notified, isTrue);
      refresh.dispose();
    });
  });
}
