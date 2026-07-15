import 'dart:async';

import 'package:flutter/foundation.dart';

/// Notifier collegato a [GoRouter.refreshListenable] per rivalutare i redirect auth.
class GoRouterAuthRefresh extends ChangeNotifier {
  bool _refreshScheduled = false;

  void scheduleRefresh() {
    if (_refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      notifyListeners();
    });
  }

  void notifyAuthChanged() {
    scheduleRefresh();
  }
}
