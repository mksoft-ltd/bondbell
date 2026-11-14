import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_log.dart';

/// Everything Bondbell keeps lives on the device. Real and sample data use
/// separate key prefixes so a demo can never leak into the user's own bonds.
///
/// Two places:
/// - SharedPreferences for flags (onboarded, sample mode, reminders, Pro).
/// - A [DataVault] file for anything holding bond numbers or holder names
///   (every `real.` and `sample.` key), when one is attached. On iOS its
///   folder is excluded from iCloud and computer backups, so the app's
///   "your numbers stay on this device" is literally true there too
///   (security audit L-2). Android excludes all app data from backup in the
///   manifest already.
///
/// Without a vault (tests, and the constructor below) every key lives in
/// SharedPreferences, which is how the app stored everything before 1.0's
/// fix round 2.
class LocalStore {
  LocalStore(this._prefs) : _vault = null;
  LocalStore.withVault(this._prefs, DataVault vault) : _vault = vault;

  final SharedPreferences _prefs;
  final DataVault? _vault;

  static bool isPrivateKey(String key) =>
      key.startsWith('real.') || key.startsWith('sample.');

  bool _inVault(String key) => _vault != null && isPrivateKey(key);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  String? getString(String key) =>
      _inVault(key) ? _vault!.get(key) : _prefs.getString(key);

  Future<void> setString(String key, String value) => _inVault(key)
      ? _vault!.set(key, value)
      : _prefs.setString(key, value).then((_) {});

  Future<void> remove(String key) =>
      _inVault(key) ? _vault!.remove(key) : _prefs.remove(key).then((_) {});

  Object? readJson(String key) {
    final String? raw = getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException catch (e) {
      // Never log `e`: its text quotes the stored JSON (bond numbers).
      appLog('Corrupt value at $key (${e.runtimeType})');
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) =>
      setString(key, jsonEncode(value));

  /// Removes every key with [prefix] (used by "Delete all my data").
  Future<void> clearPrefix(String prefix) async {
    for (final String k in _prefs.getKeys().toList()) {
      if (k.startsWith(prefix)) await _prefs.remove(k);
    }
    await _vault?.removeWhere((String k) => k.startsWith(prefix));
  }
}

/// A small JSON file of private key/value strings, read once at launch and
/// rewritten atomically (temp file + rename) on every change, in order.
class DataVault {
  DataVault._(this._file, this._values);

  final File _file;
  final Map<String, String> _values;
  Future<void> _writes = Future<void>.value();

  /// Opens (or creates) `<dir>/vault.json`. A corrupt file is kept aside as
  /// `vault.json.bak` rather than overwritten, and the vault starts empty.
  static Future<DataVault> open(Directory dir) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File f = File('${dir.path}/vault.json');
    Map<String, String> values = <String, String>{};
    if (f.existsSync()) {
      try {
        final Object? j = jsonDecode(await f.readAsString());
        values = <String, String>{
          for (final MapEntry<String, Object?> e
              in (j! as Map<String, Object?>).entries)
            e.key: e.value! as String,
        };
      } on Object catch (e) {
        appLog('Vault unreadable (${e.runtimeType}); kept as .bak');
        await f.copy('${f.path}.bak');
      }
    }
    return DataVault._(f, values);
  }

  String? get(String key) => _values[key];
  Iterable<String> get keys => _values.keys;

  Future<void> set(String key, String value) {
    _values[key] = value;
    return _flush();
  }

  Future<void> remove(String key) {
    if (_values.remove(key) == null) return _writes;
    return _flush();
  }

  Future<void> removeWhere(bool Function(String key) test) {
    final int before = _values.length;
    _values.removeWhere((String k, _) => test(k));
    return before == _values.length ? _writes : _flush();
  }

  /// Writes are chained so two quick saves can never land out of order.
  Future<void> _flush() {
    final String snapshot = jsonEncode(_values);
    _writes = _writes.then((_) async {
      try {
        final File tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(snapshot, flush: true);
        await tmp.rename(_file.path);
      } on Object catch (e) {
        appLog('Vault write failed (${e.runtimeType})');
      }
    });
    return _writes;
  }

  /// Moves every private key out of SharedPreferences into this vault (the
  /// pre-vault storage), then deletes it from prefs once the file is
  /// written. Values already in the vault win.
  Future<void> migrateFrom(SharedPreferences prefs) async {
    final List<String> moved = <String>[];
    for (final String k in prefs.getKeys()) {
      if (!LocalStore.isPrivateKey(k)) continue;
      final String? v = prefs.getString(k);
      if (v == null) continue;
      _values.putIfAbsent(k, () => v);
      moved.add(k);
    }
    if (moved.isEmpty) return;
    await _flush();
    if (!_file.existsSync()) return; // never delete before the copy exists
    for (final String k in moved) {
      await prefs.remove(k);
    }
  }
}

/// iOS: marks [dir] (and so everything in it) as excluded from iCloud and
/// computer backups via `URLResourceValues.isExcludedFromBackup`, set by
/// the method channel in AppDelegate.swift. The directory, not the file,
/// carries the flag, because each atomic save replaces the file.
const MethodChannel backupChannel = MethodChannel(
  'com.froggyeye.bondbell/backup',
);

Future<bool> excludeFromBackup(Directory dir) async {
  if (!Platform.isIOS) return true; // Android: manifest excludes all data.
  try {
    return await backupChannel.invokeMethod<bool>(
          'excludeFromBackup',
          dir.path,
        ) ??
        false;
  } on Object catch (e) {
    appLog('excludeFromBackup failed (${e.runtimeType})');
    return false;
  }
}

/// Overridden in `main()` once SharedPreferences has loaded.
final Provider<LocalStore> localStoreProvider = Provider<LocalStore>(
  (Ref ref) => throw UnimplementedError('localStoreProvider not overridden'),
);
