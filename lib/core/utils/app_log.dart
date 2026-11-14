import 'package:flutter/foundation.dart';

/// Diagnostic logging that is compiled out of release builds.
///
/// `debugPrint` is NOT removed in release: it reaches logcat and the iOS
/// unified log. Exception text can carry user data (a `FormatException`
/// from `jsonDecode` quotes the stored JSON, i.e. bond numbers and holder
/// names; security audit L-4), so every diagnostic goes through here.
/// The one release log line, the check timing in check_session.dart, uses
/// `debugPrint` deliberately and carries only timings and counts.
void appLog(String message) {
  if (!kReleaseMode) debugPrint(message);
}
