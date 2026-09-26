import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for small per-device flags that
/// don't belong in Firestore (e.g. "has this device already reacted to this
/// match with this emoji"). Not a security boundary — a user could clear app
/// data or reinstall — just a UX nicety against accidental repeat taps.
class LocalPrefsService {
  Future<bool> hasFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> setFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  Future<void> clearFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}
