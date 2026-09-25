import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks whether the device currently has any network connectivity, so the
/// UI can show an honest "you're offline" banner instead of silently relying
/// on Firestore's local cache with no indication anything is stale — this
/// matters most for admins entering scores courtside on a poor connection.
class ConnectivityState extends ChangeNotifier {
  bool isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ConnectivityState() {
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
    Connectivity().checkConnectivity().then(_onChanged);
  }

  void _onChanged(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != isOffline) {
      isOffline = offline;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
