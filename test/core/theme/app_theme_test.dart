import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/theme/app_semantic_colors.dart';
import 'package:smartfinch/core/theme/app_theme.dart';
import 'package:smartfinch/core/theme/score_colors.dart';

void main() {
  group('AppTheme variants', () {
    test(
      'standard light theme keeps brand and functional color extensions',
      () {
        final theme = AppTheme.light();
        final semanticColors = theme.extension<AppSemanticColors>()!;

        expect(AppTheme.isHighContrastTheme(theme), isFalse);
        expect(theme.colorScheme.primary, AppTheme.brandPrimary);
        expect(theme.colorScheme.onSurface, Colors.black);
        expect(theme.extension<ScoreColors>(), same(ScoreColors.light));
        expect(semanticColors.success, AppSemanticColors.light.success);
        expect(semanticColors.sessionLive, AppSemanticColors.light.sessionLive);
        expect(
          semanticColors.sessionFileAnalysis,
          AppSemanticColors.light.sessionFileAnalysis,
        );
      },
    );

    test('standard dark theme keeps brand and functional color extensions', () {
      final theme = AppTheme.dark();
      final semanticColors = theme.extension<AppSemanticColors>()!;

      expect(AppTheme.isHighContrastTheme(theme), isFalse);
      expect(theme.colorScheme.primary, AppTheme.brandPrimaryLight);
      expect(theme.extension<ScoreColors>(), same(ScoreColors.dark));
      expect(semanticColors.success, AppSemanticColors.light.success);
      expect(
        semanticColors.sessionSurvey,
        AppSemanticColors.light.sessionSurvey,
      );
    });

    test('dynamic color theme is not treated as high contrast', () {
      final theme = AppTheme.fromColorScheme(
        const ColorScheme.light(
          primary: Colors.purple,
          primaryContainer: Colors.deepPurple,
          surface: Color(0xFFFFFBFE),
        ),
      );
      final semanticColors = theme.extension<AppSemanticColors>()!;

      expect(AppTheme.isHighContrastTheme(theme), isFalse);
      expect(theme.colorScheme.primary, Colors.purple);
      expect(theme.extension<ScoreColors>(), same(ScoreColors.light));
      expect(semanticColors.success, isNot(theme.colorScheme.primary));
    });

    test('high contrast light tunes score, success, and mode colors', () {
      final theme = AppTheme.highContrastLight();
      final semanticColors = theme.extension<AppSemanticColors>()!;

      expect(AppTheme.isHighContrastTheme(theme), isTrue);
      expect(theme.colorScheme.primary, Colors.black);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.extension<ScoreColors>(), same(ScoreColors.light));
      expect(semanticColors.success, isNot(theme.colorScheme.primary));
      expect(semanticColors.success, isNot(theme.colorScheme.onSurface));

      // Mode accents are deepened for the white high-contrast surface, so they
      // differ from the standard hues, stay dark enough to be legible on white,
      // and remain distinct from one another.
      final modes = _modeAccents(semanticColors);
      expect(
        semanticColors.sessionLive,
        isNot(AppSemanticColors.light.sessionLive),
      );
      for (final accent in modes) {
        expect(
          ThemeData.estimateBrightnessForColor(accent),
          Brightness.dark,
          reason: 'high-contrast-light accent $accent must be dark on white',
        );
      }
      expect(modes.toSet(), hasLength(modes.length));
    });

    test('high contrast dark tunes score, success, and mode colors', () {
      final theme = AppTheme.highContrastDark();
      final semanticColors = theme.extension<AppSemanticColors>()!;

      expect(AppTheme.isHighContrastTheme(theme), isTrue);
      expect(theme.colorScheme.primary, Colors.white);
      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.extension<ScoreColors>(), same(ScoreColors.dark));
      expect(semanticColors.success, isNot(theme.colorScheme.primary));
      expect(semanticColors.success, isNot(theme.colorScheme.onSurface));

      // Mode accents are brightened for the black high-contrast surface.
      final modes = _modeAccents(semanticColors);
      expect(
        semanticColors.sessionSurvey,
        isNot(AppSemanticColors.light.sessionSurvey),
      );
      for (final accent in modes) {
        expect(
          ThemeData.estimateBrightnessForColor(accent),
          Brightness.light,
          reason: 'high-contrast-dark accent $accent must be light on black',
        );
      }
      expect(modes.toSet(), hasLength(modes.length));
    });
  });
}

/// The six session-mode accent colors, in a stable order for distinctness
/// checks.
List<Color> _modeAccents(AppSemanticColors c) => [
  c.sessionLive,
  c.sessionPointCount,
  c.sessionSurvey,
  c.sessionFileAnalysis,
  c.sessionBatchAnalysis,
  c.sessionAru,
];
