// Host side of `flutter drive` for integration_test/screenshots_test.dart:
// writes each binding.takeScreenshot() to build/screenshots/<name>.png.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final File f = File('build/screenshots/$name.png')
          ..createSync(recursive: true);
        f.writeAsBytesSync(bytes);
        return true;
      },
);
