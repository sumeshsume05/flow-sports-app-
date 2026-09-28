import 'dart:convert';
import 'dart:io';

import 'package:apk_sideload/install_apk.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/app_update_info.dart';

/// The stable Hosting URL the publish script always overwrites — never a
/// per-release URL, so a WhatsApp link shared once stays valid forever (new
/// installs get whatever's current; existing installs get prompted in-app).
const _versionJsonUrl = 'https://flow-sports-2026.web.app/version.json';

/// Checks Firebase Hosting for a newer release, downloads it with progress,
/// and hands off to Android's package installer. A failed check is treated
/// as "no update available" rather than an error — a flaky network shouldn't
/// block anyone from using the app normally.
class AppUpdateService {
  Future<AppUpdateInfo?> fetchLatestVersion() async {
    try {
      final response = await http.get(Uri.parse(_versionJsonUrl)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return AppUpdateInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] to the app's cache dir (already covered by the
  /// installer plugin's bundled FileProvider paths), reporting progress as
  /// 0.0–1.0. Returns the downloaded file.
  Future<File> downloadApk(String url, {required void Function(double progress) onProgress}) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final total = response.contentLength ?? 0;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/flow-arena-update.apk');
    final sink = file.openWrite();

    var received = 0;
    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) onProgress(received / total);
      return chunk;
    }).pipe(sink);
    await sink.close();

    return file;
  }

  Future<void> installApk(String filePath) => InstallApk().installApk(filePath);
}
