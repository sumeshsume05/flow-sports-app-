import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists this device's chat identity (a random id + a chosen display
/// name) and a lightweight send rate-limit — all locally, no auth required.
/// Not a security boundary: it's a UX guard against accidental double-sends,
/// and a client-side speed bump against spam, mirroring the trust level
/// already accepted for reactions (see [LocalPrefsService]).
class LocalIdentityService {
  static const _deviceIdKey = 'chat_device_id';
  static const _displayNameKey = 'chat_display_name';
  static const _lastSentAtKey = 'chat_last_sent_at_ms';
  static const _lastReadAtKey = 'chat_last_read_at_ms';
  static const minSendGap = Duration(seconds: 3);

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _randomId();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }

  /// Whether enough time has passed since the last send to allow another one.
  Future<bool> canSendNow() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastSentAtKey);
    if (lastMs == null) return true;
    final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
    return elapsed >= minSendGap;
  }

  Future<void> recordSentNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSentAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// When this device last had the chat screen open — drives the unread
  /// badge on [ChatFab]. Null means "never read", i.e. everything is unread.
  Future<DateTime?> getLastReadAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastReadAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markReadNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastReadAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  String _randomId() {
    final rand = Random();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
