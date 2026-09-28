/// Parsed shape of `release/version.json`, published by `scripts/publish_release.sh`
/// to Firebase Hosting. See that script for the exact fields it writes.
class AppUpdateInfo {
  final int latestVersionCode;
  final String latestVersionName;
  final String apkUrl;
  final bool forceUpdate;
  final String? changelog;

  const AppUpdateInfo({
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.apkUrl,
    required this.forceUpdate,
    this.changelog,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        latestVersionCode: json['latestVersionCode'] as int,
        latestVersionName: json['latestVersionName'] as String,
        apkUrl: json['apkUrl'] as String,
        forceUpdate: json['forceUpdate'] as bool? ?? false,
        changelog: json['changelog'] as String?,
      );
}
