// =============================================================================
// AppHaptics — SET-04, the vibration switch
// =============================================================================
//
// Two things, and the second is the one that keeps the first true:
//
//   **The switch silences the vibration.** Off means the platform is never
//   asked to vibrate; on (the default) means it is.
//
//   **Nothing goes around it.** A `HapticFeedback` call added anywhere else in
//   the app would vibrate with the switch off and nobody would notice until a
//   parent did. So the source is searched for one.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/constants/app_constants.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/utils/app_haptics.dart';

void main() {
  /// Pumps a button that vibrates through [AppHaptics], and records every
  /// vibration the platform is asked for.
  Future<List<String>> pressWith(WidgetTester tester, {bool? enabled}) async {
    SharedPreferences.setMockInitialValues({
      if (enabled != null) PrefKeys.hapticsEnabled: enabled,
    });
    final prefs = await SharedPreferences.getInstance();

    final vibrations = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          vibrations.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    AppHaptics.lightImpact(context);
                    AppHaptics.mediumImpact(context);
                    AppHaptics.selectionClick(context);
                  },
                  child: const Text('press'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('press'));
    await tester.pump();
    return vibrations;
  }

  testWidgets('on by default: every kind of vibration reaches the platform', (
    tester,
  ) async {
    final vibrations = await pressWith(tester);

    expect(vibrations, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('switched off, the platform is never asked to vibrate', (
    tester,
  ) async {
    expect(await pressWith(tester, enabled: false), isEmpty);
  });

  test('the cue without a context follows the value it is given', () async {
    final vibrations = <String>[];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            vibrations.add('${call.arguments}');
          }
          return null;
        });

    await AppHaptics.selectionClickIf(false);
    expect(vibrations, isEmpty);
    await AppHaptics.selectionClickIf(true);
    expect(vibrations, hasLength(1));
  });

  test('nothing in the app vibrates except through AppHaptics', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('app_haptics.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (line.contains('HapticFeedback.')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Vibrate through AppHaptics, so the switch in Settings applies '
          '(SET-04).',
    );
  });
}
