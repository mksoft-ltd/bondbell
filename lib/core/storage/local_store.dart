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

  /// True when written. Private keys go to the vault; a false there means
  /// nothing changed (see [DataVault]).
  Future<bool> setString(String key, String value) => _inVault(key)
      ? _vault!.set(key, value)
      : _prefs.setString(key, value);

  Future<bool> remove(String key) =>
      _inVault(key) ? _vault!.remove(key) : _prefs.remove(key);

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

  Future<bool> writeJson(String key, Object? value) =>
      setString(key, jsonEncode(value));

  /// Removes every key with [prefix] from both places.
  Future<bool> clearPrefix(String prefix) async {
    bool ok = true;
    for (final String k in _prefs.getKeys().toList()) {
      if (k.startsWith(prefix)) ok = await _prefs.remove(k) && ok;
    }
    final DataVault? v = _vault;
    if (v != null) {
      ok = await v.removeWhere((String k) => k.startsWith(prefix)) && ok;
    }
    return ok;
  }

  /// "Delete all my data": every holder, bond number and result, real and
  /// sample, plus the vault's side files. Settings (onboarding, sample
  /// mode, reminders) and the Pro unlock are kept. True when all of it
  /// went.
  Future<bool> deleteAllPrivateData() async {
    final bool real = await clearPrefix('real.');
    final bool sample = await clearPrefix('sample.');
    final bool files = await _vault?.deleteLeftovers() ?? true;
    return real && sample && files;
  }
}

/// How the vault was found at launch.
enum VaultOpenStatus {
  /// Readable (or not created yet). Nothing to tell the user.
  ok,

  /// `vault.json` was unreadable; the copy saved at the previous launch was
  /// restored. Changes made since then may be missing.
  recovered,

  /// `vault.json` was unreadable and there was no usable earlier copy; the
  /// app starts without the user's bonds. The damaged file is kept aside.
  lost,
}

/// Thrown by the controllers when a change could not be written to the
/// device (disk full, a file-protection error). The change is NOT applied
/// in memory either, so the screen never shows something as saved that
/// will be gone at the next launch (code review N1).
class SaveFailedException implements Exception {
  const SaveFailedException();
  static const String message =
      'Bondbell couldn\'t save this change on your device. It may be out of '
      'storage space. Please free some space and try again.';
  @override
  String toString() => message;
}

/// A small JSON file of private key/value strings, read once at launch and
/// rewritten atomically (temp file + rename) on every change, in order.
///
/// Files in its folder (all inside the backup-excluded directory on iOS):
/// - `vault.json`: the data.
/// - `vault.json.bak`: the last copy that opened cleanly (refreshed at each
///   launch), used to recover if `vault.json` is ever unreadable.
/// - `vault.json.corrupt-<millis>`: a damaged file, kept aside, never
///   overwritten.
/// - `vault.json.tmp`: only ever mid-save.
class DataVault {
  DataVault._(this._dir, this._file, this._values, this.status);

  final Directory _dir;
  final File _file;

  /// Committed values: what is on disk. Changes land here only after the
  /// write succeeds.
  final Map<String, String> _values;
  final VaultOpenStatus status;
  Future<void> _writes = Future<void>.value();

  static const String fileName = 'vault.json';

  static Map<String, String>? _read(File f) {
    try {
      if (!f.existsSync()) return null;
      final Object? j = jsonDecode(f.readAsStringSync());
      return <String, String>{
        for (final MapEntry<String, Object?> e
            in (j! as Map<String, Object?>).entries)
          e.key: e.value! as String,
      };
    } on Object catch (e) {
      appLog('Vault file unreadable (${e.runtimeType})');
      return null;
    }
  }

  /// Opens (or creates) `<dir>/vault.json`, recovering from the last good
  /// copy if it is unreadable. See [status].
  static Future<DataVault> open(Directory dir) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File f = File('${dir.path}/$fileName');
    final File bak = File('${f.path}.bak');
    if (!f.existsSync()) {
      return DataVault._(dir, f, <String, String>{}, VaultOpenStatus.ok);
    }
    final Map<String, String>? values = _read(f);
    if (values != null) {
      // Remember this good state for recovery next time.
      try {
        await f.copy(bak.path);
      } on Object catch (e) {
        appLog('Vault backup copy failed (${e.runtimeType})');
      }
      return DataVault._(dir, f, values, VaultOpenStatus.ok);
    }
    // Damaged: keep it aside (never overwriting an earlier one), then try
    // the last good copy.
    try {
      await f.rename(
        '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    } on Object catch (e) {
      appLog('Vault set-aside failed (${e.runtimeType})');
    }
    final Map<String, String>? recovered = _read(bak);
    if (recovered == null) {
      return DataVault._(dir, f, <String, String>{}, VaultOpenStatus.lost);
    }
    final DataVault v =
        DataVault._(dir, f, recovered, VaultOpenStatus.recovered);
    await v._commit(Map<String, String>.of(recovered));
    return v;
  }

  String? get(String key) => _values[key];
  Iterable<String> get keys => _values.keys;

  /// True when the change was written. On false nothing changed.
  Future<bool> set(String key, String value) =>
      _change((Map<String, String> m) => m[key] = value);

  Future<bool> remove(String key) =>
      _change((Map<String, String> m) => m.remove(key));

  Future<bool> removeWhere(bool Function(String key) test) =>
      _change((Map<String, String> m) => m.removeWhere((String k, _) => test(k)));

  /// Applies [edit] to a copy of the committed values and writes it. Steps
  /// are chained, and each starts from the values committed by the step
  /// before, so quick successive changes land in order and a failed write
  /// never leaks into memory.
  Future<bool> _change(void Function(Map<String, String> m) edit) {
    final Completer<bool> done = Completer<bool>();
    _writes = _writes.then((_) async {
      final Map<String, String> next = Map<String, String>.of(_values);
      edit(next);
      done.complete(await _commit(next));
    });
    return done.future;
  }

  Future<bool> _commit(Map<String, String> next) async {
    try {
      final File tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(next), flush: true);
      await tmp.rename(_file.path);
    } on Object catch (e) {
      appLog('Vault write failed (${e.runtimeType})');
      return false;
    }
    _values
      ..clear()
      ..addAll(next);
    return true;
  }

  /// Deletes the vault's side files (last-good copy, set-aside damaged
  /// files, an interrupted temp file) once it holds no private data, so
  /// "Delete all my data" leaves no copy behind (security N-1).
  Future<bool> deleteLeftovers() async {
    if (_values.keys.any(LocalStore.isPrivateKey)) return false;
    bool ok = true;
    for (final FileSystemEntity e in _dir.listSync()) {
      final String name = e.uri.pathSegments.last;
      if (name == fileName) continue;
      if (!name.startsWith('$fileName.')) continue;
      try {
        e.deleteSync();
      } on Object catch (err) {
        appLog('Leftover delete failed (${err.runtimeType})');
        ok = false;
      }
    }
    return ok;
  }

  /// Moves every private key out of SharedPreferences into this vault (the
  /// pre-vault storage), then deletes it from prefs once the file is
  /// written. Values already in the vault win.
  Future<void> migrateFrom(SharedPreferences prefs) async {
    final Map<String, String> found = <String, String>{};
    for (final String k in prefs.getKeys()) {
      if (!LocalStore.isPrivateKey(k)) continue;
      final String? v = prefs.getString(k);
      if (v != null) found[k] = v;
    }
    if (found.isEmpty) return;
    final bool ok = await _change((Map<String, String> m) {
      found.forEach((String k, String v) => m.putIfAbsent(k, () => v));
    });
    if (!ok) return; // never delete before the copy exists
    for (final String k in found.keys) {
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

/// How the data vault opened this launch; overridden in `main()`. Anything
/// but [VaultOpenStatus.ok] is explained to the user once (AppHooks).
final Provider<VaultOpenStatus> vaultStatusProvider =
    Provider<VaultOpenStatus>((Ref ref) => VaultOpenStatus.ok);

/// The plain-language explanation for a vault that didn't open cleanly.
String? vaultStatusMessage(VaultOpenStatus s) => switch (s) {
  VaultOpenStatus.ok => null,
  VaultOpenStatus.recovered =>
    'Bondbell\'s saved data on this device was damaged, so it has restored '
        'the copy saved when the app was last opened. Please check your '
        'bonds: anything you changed after that may be missing.',
  VaultOpenStatus.lost =>
    'Bondbell\'s saved data on this device was damaged and couldn\'t be '
        'recovered, so your holders, bond numbers and results are missing. '
        'Please add your bonds again. Nothing was sent anywhere.',
};

/// Overridden in `main()` once SharedPreferences has loaded.
final Provider<LocalStore> localStoreProvider = Provider<LocalStore>(
  (Ref ref) => throw UnimplementedError('localStoreProvider not overridden'),
);
