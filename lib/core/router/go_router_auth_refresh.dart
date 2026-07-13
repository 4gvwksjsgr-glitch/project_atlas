import 'package:flutter/foundation.dart';

/// Notifier collegato a [GoRouter.refreshListenable] per rivalutare i redirect auth.
class GoRouterAuthRefresh extends ChangeNotifier {
  void notifyAuthChanged() {
    notifyListeners();
  }
}
