// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'package:golden_tests_harvester/golden_tests_harvester.dart';
import 'package:litetest/litetest.dart';
import 'package:path/path.dart' as p;

void main() async {
  Future<void> withTempDirectory(FutureOr<void> Function(io.Directory) callback) async {
    final io.Directory tempDirectory = await io.Directory.systemTemp.createTemp('golden_tests_harvester_test.');
    try {
      await callback(tempDirectory);
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }

  test('should fail on a missing directory', () async {
    await withTempDirectory((io.Directory tempDirectory) async {
      final StringSink stderr = StringBuffer();
      final ArgumentError error = await _expectThrow<ArgumentError>(() async {
        await harvest(
          workDirectory: io.Directory(p.join(tempDirectory.path, 'non_existent')),
          addImg: _alwaysThrowsAddImg,
          stderr: stderr,
        );
      });
      expect(error.message, contains('non_existent'));
      expect(stderr.toString(), isEmpty);
    });
  });

  test('should require a file named "digest.json" in the working directory', () async {
    await withTempDirectory((io.Directory tempDirectory) async {
      final StringSink stderr = StringBuffer();

      final StateError error = await _expectThrow<StateError>(() async {
        await harvest(
          workDirectory: tempDirectory,
          addImg: _alwaysThrowsAddImg,
          stderr: stderr,
        );
      });
      expect(error.toString(), contains('digest.json'));
      expect(stderr.toString(), isEmpty);
    });
  });

  test('should throw if "digest.json" is in an unexpected format', () async {
    await withTempDirectory((io.Directory tempDirectory) async {
      final StringSink stderr = StringBuffer();
      final io.File digestsFile = io.File(p.join(tempDirectory.path, 'digest.json'));
      await digestsFile.writeAsString('{"dimensions": "not a map", "entries": []}');

      final FormatException error = await _expectThrow<FormatException>(() async {
        await harvest(
          workDirectory: tempDirectory,
          addImg: _alwaysThrowsAddImg,
          stderr: stderr,
        );
      });
      expect(error.message, contains('dimensions'));
      expect(stderr.toString(), isEmpty);
    });
  });

  test('should fail eagerly if addImg fails', () async {
    await withTempDirectory((io.Directory tempDirectory) async {
      final io.File digestsFile = io.File(p.join(tempDirectory.path, 'digest.json'));
      final StringSink stderr = StringBuffer();
      await digestsFile.writeAsString('''
        {
          "dimensions": {},
          "entries": [
            {
              "filename": "test_name_1.png",
              "width": 100,
              "height": 100,
              "maxDiffPixelsPercent": 0.01,
              "maxColorDelta": 0
            }
          ]
        }
      ''');

      final FailedComparisonException error = await _expectThrow<FailedComparisonException>(() async {
        await harvest(
          workDirectory: tempDirectory,
          addImg: _alwaysThrowsAddImg,
          stderr: stderr,
        );
      });
      expect(error.testName, 'test_name_1.png');
      expect(stderr.toString(), contains('IntentionalError'));
    });
  });

  test('should invoke addImg per test', () async {
    await withTempDirectory((io.Directory tempDirectory) async {
      final io.File digestsFile = io.File(p.join(tempDirectory.path, 'digest.json'));
      await digestsFile.writeAsString('''
        {
          "dimensions": {},
          "entries": [
            {
              "filename": "test_name_1.png",
              "width": 100,
              "height": 100,
              "maxDiffPixelsPercent": 0.01,
              "maxColorDelta": 0
            },
            {
              "filename": "test_name_2.png",
              "width": 200,
              "height": 200,
              "maxDiffPixelsPercent": 0.02,
              "maxColorDelta": 1
            }
          ]
        }
      ''');
      final List<String> addImgCalls = <String>[];
      final StringSink stderr = StringBuffer();
      await harvest(
        workDirectory: tempDirectory,
        addImg: (
          String testName,
          io.File goldenFile, {
          required int screenshotSize,
          double differentPixelsRate = 0.01,
          int pixelColorDelta = 0,
        }) async {
          addImgCalls.add('$testName $screenshotSize $differentPixelsRate $pixelColorDelta');
        },
        stderr: stderr,
      );
      expect(addImgCalls, <String>[
        'test_name_1.png 10000 0.01 0',
        'test_name_2.png 40000 0.02 1',
      ]);
    });

  });
}

FutureOr<T> _expectThrow<T extends Object>(FutureOr<void> Function() callback) async {
  try {
    await callback();
    fail('Expected an exception of type $T');
  } on T catch (e) {
    return e;
  } catch (e) {
    fail('Expected an exception of type $T, but got $e');
  }
  // fail(...) unfortunately does not return Never, but it does always throw.
  throw UnsupportedError('Unreachable');
}

final class _IntentionalError extends Error {}

Future<void> _alwaysThrowsAddImg(
  String testName,
  io.File goldenFile, {
  required int screenshotSize,
  double differentPixelsRate = 0.01,
  int pixelColorDelta = 0,
}) async {
  throw _IntentionalError();
}
