import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything Bondbell keeps lives on the device in SharedPreferences as
/// small JSON values. Real and sample data use separate key prefixes so a
/// demo can never leak into the user's own bonds.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  Object? readJson(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException catch (e) {
      debugPrint('Corrupt value at $key: $e');
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) =>
      _prefs.setString(key, jsonEncode(value));

  /// Removes every key with [prefix] (used by "Delete all my data").
  Future<void> clearPrefix(String prefix) async {
    for (final String k in _prefs.getKeys().toList()) {
      if (k.startsWith(prefix)) await _prefs.remove(k);
    }
  }
}

/// Overridden in `main()` once SharedPreferences has loaded.
final Provider<LocalStore> localStoreProvider = Provider<LocalStore>(
  (Ref ref) => throw UnimplementedError('localStoreProvider not overridden'),
);
