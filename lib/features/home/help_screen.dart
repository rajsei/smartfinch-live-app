// =============================================================================
// Help Screen — Comprehensive app help clustered by mode
// =============================================================================
//
// A dedicated help screen accessible from the home screen footer. Explains
// each app mode and general tips for best results, organized into expandable
// sections.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/link_launcher.dart';
import '../../shared/utils/session_type_visuals.dart';
import '../../shared/widgets/content_width_constraint.dart';
import '../live/live_session.dart';

/// Comprehensive help screen with mode-by-mode explanations.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isBrandTheme = isBrandThemeColorScheme(theme.colorScheme);
    final highContrast = AppTheme.isHighContrastTheme(theme);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpTitle)),
      body: ContentWidthConstraint(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // ── 1. Introduction ─────────────────────────────────
            // Sets context for everything that follows: what kind of app
            // this is and how the help page is organized.
            Text(
              l10n.helpIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    highContrast
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withAlpha(200),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // ── 2. What you can do ──
            // The user's primary intent on opening the app is to listen and
            // find out what is singing, so Live comes first. Point Count,
            // Survey, File Analysis, Batch Analysis and ARU were removed in
            // transition step 0.3; their help sections went with them.
            _SectionHeader(
              icon: AppIcons.micNoneOutlined,
              title: l10n.helpModesTitle,
            ),
            const SizedBox(height: 12),
            _HelpSection(
              icon: sessionTypeIcon(SessionType.live),
              color: sessionTypeAccentColor(theme, SessionType.live),
              containerColor:
                  isBrandTheme
                      ? sessionTypeAccentColor(
                        theme,
                        SessionType.live,
                      ).withAlpha(30)
                      : sessionTypeContainerColor(theme, SessionType.live),
              title: l10n.helpLiveTitle,
              body: l10n.helpLiveBody,
            ),
            const SizedBox(height: 20),

            // ── 3. Discover & revisit (Explore + Session Library) ──
            // Once the user has captured something — or wants to know
            // *what to expect* before recording — these two screens are
            // where they go.
            _SectionHeader(
              icon: AppIcons.travelExplore,
              title: l10n.helpToolsTitle,
            ),
            const SizedBox(height: 12),
            _HelpSection(
              icon: AppIcons.searchRounded,
              color: theme.colorScheme.primary,
              containerColor: theme.colorScheme.primaryContainer,
              title: l10n.helpExploreTitle,
              body: l10n.helpExploreBody,
            ),
            _HelpSection(
              icon: AppIcons.libraryBooks,
              color: theme.colorScheme.secondary,
              containerColor: theme.colorScheme.secondaryContainer,
              title: l10n.helpSessionsTitle,
              body: l10n.helpSessionsBody,
            ),
            const SizedBox(height: 20),

            // ── 4. Common controls (settings & meta navigation) ──
            // These are the small AppBar / footer affordances common to
            // every screen. They follow the modes because users typically
            // discover them only after they've started using the app.
            _SectionHeader(
              icon: AppIcons.gridViewRounded,
              title: l10n.helpControlsTitle,
            ),
            const SizedBox(height: 12),
            _ControlCard(
              icon: AppIcons.tuneRounded,
              title: l10n.settings,
              body: l10n.helpControlSettings,
            ),
            _ControlCard(
              icon: AppIcons.helpOutlineRounded,
              title: l10n.helpTitle,
              body: l10n.helpControlHelp,
            ),
            _ControlCard(
              icon: AppIcons.infoOutline,
              title: l10n.about,
              body: l10n.helpControlAbout,
            ),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),

            // ── 5. Tips for best results ─────────────────────────
            _SectionHeader(
              icon: AppIcons.lightbulbOutline,
              title: l10n.helpTipsTitle,
            ),
            const SizedBox(height: 12),
            _TipRow(text: l10n.helpTipQuiet),
            _TipRow(text: l10n.helpTipMic),
            _TipRow(text: l10n.helpTipBasics),
            _TipRow(text: l10n.helpTipThreshold),
            _TipRow(text: l10n.helpTipGeoFilter),
            _TipRow(text: l10n.helpTipGuide),
            const SizedBox(height: 12),

            // ── 6. Deeper dive — link out to the online user guide ──
            Card(
              color:
                  highContrast
                      ? theme.colorScheme.surface
                      : theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          AppIcons.menuBook,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.aboutUserGuide,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.helpTipGuide,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            highContrast
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withAlpha(180),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _launchUserGuide(context),
                      icon: const Icon(AppIcons.openInNew),
                      label: Text(l10n.aboutUserGuide),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header — small icon + title row used between top-level help
// groups. Kept inline here (rather than promoted to a shared widget)
// because the layout is intentionally tied to this screen's rhythm.
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Help Section — Expandable card for a single mode
// ─────────────────────────────────────────────────────────────────────────────

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.color,
    required this.containerColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final Color containerColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = AppTheme.isHighContrastTheme(theme);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color:
          highContrast
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(highContrast ? 8 : 12),
        side:
            highContrast
                ? BorderSide(color: theme.colorScheme.outline)
                : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: highContrast ? theme.colorScheme.surface : containerColor,
            borderRadius: BorderRadius.circular(10),
            border:
                highContrast
                    ? Border.all(color: theme.colorScheme.outline)
                    : null,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  highContrast
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withAlpha(200),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = AppTheme.isHighContrastTheme(theme);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color:
          highContrast
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(highContrast ? 8 : 12),
        side:
            highContrast
                ? BorderSide(color: theme.colorScheme.outline)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color:
                    highContrast
                        ? theme.colorScheme.surface
                        : theme.colorScheme.primary.withAlpha(24),
                borderRadius: BorderRadius.circular(10),
                border:
                    highContrast
                        ? Border.all(color: theme.colorScheme.outline)
                        : null,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          highContrast
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withAlpha(180),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tip Row — Bullet-style tip
// ─────────────────────────────────────────────────────────────────────────────

class _TipRow extends StatelessWidget {
  const _TipRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = AppTheme.isHighContrastTheme(theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(
              AppIcons.chevronRight,
              size: 16,
              color:
                  highContrast
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withAlpha(180),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    highContrast
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withAlpha(180),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _launchUserGuide(BuildContext context) async {
  final localeCode = Localizations.localeOf(context).languageCode;
  final basePath = AppConstants.docsLocalePrefix(localeCode);
  await openExternalUrl(context, '${AppConstants.docsUrl}$basePath/user/');
}
