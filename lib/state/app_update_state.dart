import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_info.dart';
import '../services/app_update_service.dart';

/// Checks once per app launch (not a live stream — Firebase Hosting doesn't
/// push updates the way Firestore does) whether a newer release exists.
/// `updateAvailable` is only set once both the installed version and the
/// remote manifest have resolved and the remote one is actually newer.
class AppUpdateState extends ChangeNotifier {
  final AppUpdateService _service;
  AppUpdateInfo? latest;
  bool updateAvailable = false;
  bool checked = false;

  AppUpdateState({AppUpdateService? service}) : _service = service ?? AppUpdateService();

  Future<void> checkForUpdate() async {
    final info = await _service.fetchLatestVersion();
    if (info == null) {
      checked = true;
      notifyListeners();
      return;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final installedVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

    latest = info;
    updateAvailable = info.latestVersionCode > installedVersionCode;
    checked = true;
    notifyListeners();
  }
}
