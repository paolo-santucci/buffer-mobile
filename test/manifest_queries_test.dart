import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest.xml <queries> block', () {
    late String manifest;

    setUpAll(() {
      final file = File('android/app/src/main/AndroidManifest.xml');
      manifest = file.readAsStringSync();
    });

    test('contains a <queries> element', () {
      expect(manifest, contains('<queries>'));
    });

    test('declares android.intent.action.VIEW + android:scheme="https"', () {
      // Both the VIEW action and https scheme must be present together in the
      // queries block. We check both strings are present — the structure test
      // below validates they appear in the correct context.
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android:scheme="https"'));
    });

    test('declares android.intent.action.VIEW + android:scheme="http"', () {
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android:scheme="http"'));
    });

    test('VIEW + https intent is present in the <queries> block', () {
      // Ensure the https scheme entry lives inside <queries> by checking the
      // textual proximity: the scheme attribute should appear between
      // <queries> and </queries>.
      final queriesStart = manifest.indexOf('<queries>');
      final queriesEnd = manifest.lastIndexOf('</queries>');
      expect(
        queriesStart,
        isNot(-1),
        reason: '<queries> opening tag not found',
      );
      expect(queriesEnd, isNot(-1), reason: '</queries> closing tag not found');

      final queriesBlock = manifest.substring(queriesStart, queriesEnd);
      expect(queriesBlock, contains('android.intent.action.VIEW'));
      expect(queriesBlock, contains('android:scheme="https"'));
    });

    test('VIEW + http intent is present in the <queries> block', () {
      final queriesStart = manifest.indexOf('<queries>');
      final queriesEnd = manifest.lastIndexOf('</queries>');
      final queriesBlock = manifest.substring(queriesStart, queriesEnd);
      expect(queriesBlock, contains('android.intent.action.VIEW'));
      expect(queriesBlock, contains('android:scheme="http"'));
    });

    // Regression: the existing PROCESS_TEXT query must be preserved.
    test('existing PROCESS_TEXT query is still present', () {
      expect(manifest, contains('android.intent.action.PROCESS_TEXT'));
    });

    // Regression: the M2 SEND intent-filter must be preserved.
    test('existing SEND intent-filter is still present', () {
      expect(manifest, contains('android.intent.action.SEND'));
    });

    // Structural: exactly one <queries> element (no duplicate blocks).
    test('contains exactly one <queries> opening tag', () {
      final count = '<queries>'.allMatches(manifest).length;
      expect(count, 1, reason: 'Expected exactly one <queries> block');
    });
  });
}
