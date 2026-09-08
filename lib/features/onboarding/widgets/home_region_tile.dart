// =============================================================================
// HomeRegionTile — where the child lives (SET-09, KID-01, D18)
// =============================================================================
//
// `SET-09` was raised to P0 for one reason: **without a position there is no
// rarity level, and therefore no stars** (gap F). A child who skips this does
// not get a slightly worse app — they get one that awards nothing and cannot
// explain why.
//
// So it happens during onboarding, and it shares the permissions screen rather
// than adding a fifth one (`KID-01` allows four).
//
// ### Two ways in, because one of them has to work offline
//
// With location granted, there is nothing to do: the app already knows. Without
// it — declined, unavailable, or a desktop build — the child picks a place on
// a **map**. Not a latitude field: `SET-09` is explicit that this has to work
// for a child, and two decimal numbers are not something an eight-year-old
// has.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../../shared/providers/settings_providers.dart';
import '../../../shared/widgets/map_picker_screen.dart';

/// Sets the home region during onboarding (`SET-09`).
class HomeRegionTile extends ConsumerWidget {
  const HomeRegionTile({
    super.key,
    required this.locationGranted,
    required this.theme,
  });

  /// Whether the location permission has been granted.
  final bool locationGranted;

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final lat = ref.watch(manualLatitudeProvider);
    final lon = ref.watch(manualLongitudeProvider);
    final hasManualHome = !ref.watch(useGpsProvider) && lat != 0 && lon != 0;

    // Location granted: the app already knows, and asking again would be a
    // question with no purpose.
    if (locationGranted) {
      return _Panel(
        theme: theme,
        icon: AppIcons.locationOn,
        title: l10n.onboardingHomeRegionTitle,
        body: l10n.onboardingHomeRegionFromGps,
      );
    }

    return _Panel(
      theme: theme,
      icon: hasManualHome ? AppIcons.locationOn : AppIcons.mapSheet,
      title: l10n.onboardingHomeRegionTitle,
      body:
          hasManualHome
              ? l10n.onboardingHomeRegionPicked
              : l10n.onboardingHomeRegionWhy,
      action: FilledButton.tonalIcon(
        onPressed: () => _pick(context, ref, lat: lat, lon: lon),
        icon: const Icon(AppIcons.mapSheet, size: 18),
        label: Text(
          hasManualHome
              ? l10n.onboardingHomeRegionChange
              : l10n.onboardingHomeRegionPick,
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required double lat,
    required double lon,
  }) async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder:
            (_) => MapPickerScreen(
              initialLat: lat == 0 ? null : lat,
              initialLon: lon == 0 ? null : lon,
            ),
      ),
    );
    if (picked == null) return;

    // Picking a home on the map *is* choosing not to use GPS, so both are set
    // together. Leaving `useGps` on would mean the coordinates the child just
    // chose were ignored the moment a fix arrived.
    await ref.read(manualLatitudeProvider.notifier).set(picked.latitude);
    await ref.read(manualLongitudeProvider.notifier).set(picked.longitude);
    await ref.read(useGpsProvider.notifier).set(false);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.theme,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final ThemeData theme;
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
