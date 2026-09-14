/// Хост-сторона съёмки скриншотов: складывает кадры с симулятора в
/// docs/screenshots/.
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (name, image, [args]) async {
        final file = File('docs/screenshots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(image);
        return true;
      },
    );
