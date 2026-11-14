import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.sampleMode = false,
    this.remindersEnabled = false,
  });

  final bool onboarded;

  /// Everything runs against bundled made-up lists and a sample holder.
  final bool sampleMode;
  final bool remindersEnabled;

  AppSettings copyWith({
    bool? onboarded,
    bool? sampleMode,
    bool? remindersEnabled,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    sampleMode: sampleMode ?? this.sampleMode,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
  );
}

class AppSettingsController extends Notifier<AppSettings> {
  static const String _onboardedKey = 'settings.onboarded';
  static const String _sampleKey = 'settings.sampleMode';
  static const String _remindersKey = 'settings.reminders';

  LocalStore get _store => ref.read(localStoreProvider);

  @override
  AppSettings build() => AppSettings(
    onboarded: _store.getBool(_onboardedKey) ?? false,
    sampleMode: _store.getBool(_sampleKey) ?? false,
    remindersEnabled: _store.getBool(_remindersKey) ?? false,
  );

  Future<void> completeOnboarding({required bool sampleMode}) async {
    await _store.setBool(_onboardedKey, true);
    await _store.setBool(_sampleKey, sampleMode);
    state = state.copyWith(onboarded: true, sampleMode: sampleMode);
  }

  Future<void> setSampleMode(bool on) async {
    await _store.setBool(_sampleKey, on);
    state = state.copyWith(sampleMode: on);
  }

  Future<void> setRemindersEnabled(bool on) async {
    await _store.setBool(_remindersKey, on);
    state = state.copyWith(remindersEnabled: on);
  }
}

final NotifierProvider<AppSettingsController, AppSettings>
appSettingsProvider = NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

/// Narrow read: rebuilds only when sample mode flips.
final Provider<bool> sampleModeProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(appSettingsProvider.select((AppSettings s) => s.sampleMode)),
);

/// Key prefix for data that differs between real and sample mode.
final Provider<String> dataScopeProvider = Provider<String>(
  (Ref ref) => ref.watch(sampleModeProvider) ? 'sample.' : 'real.',
);
