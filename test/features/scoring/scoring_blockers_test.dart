// =============================================================================
// What is stopping the stars — one list, read by the live bar and settings
// =============================================================================
//
// The list is the contract between two screens: the live bar names what is on
// it, the settings screen highlights where each item lives. Both read it, so a
// reason cannot be named in one place and missing from the other. What is
// tested here is the list itself: what goes on it, what does not, and the
// order the screens rely on.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/services/location_service.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/scoring/scoring_blockers.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

const _berlin = AppLocation(latitude: 52.52, longitude: 13.405);

void main() {
  /// A container whose position lookup returns what [location] does.
  Future<ProviderContainer> containerWith({
    Map<String, Object> prefs = const {},
    required Future<AppLocation?> Function() location,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentLocationProvider.overrideWith((ref) => location()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The list once the position lookup has finished, however it finished.
  Future<List<ScoringBlocker>> settled(ProviderContainer container) async {
    try {
      await container.read(currentLocationProvider.future);
    } catch (_) {
      // A failed lookup is one of the cases under test.
    }
    return container.read(scoringBlockersProvider);
  }

  test('empty while scoring works', () async {
    final container = await containerWith(location: () async => _berlin);

    expect(await settled(container), isEmpty);
  });

  test('the species filter switched off', () async {
    final container = await containerWith(
      prefs: const {'species_filter_mode': 'off'},
      location: () async => _berlin,
    );

    expect(await settled(container), [ScoringBlocker.speciesFilterOff]);
  });

  test('the threshold below the floor, but not on it', () async {
    final below = await containerWith(
      prefs: const {'confidence_threshold': 34},
      location: () async => _berlin,
    );
    expect(await settled(below), [ScoringBlocker.thresholdBelowFloor]);

    // 35 is the floor itself, and the floor still scores.
    final on = await containerWith(
      prefs: const {'confidence_threshold': 35},
      location: () async => _berlin,
    );
    expect(await settled(on), isEmpty);
  });

  test('no position', () async {
    final container = await containerWith(location: () async => null);

    expect(await settled(container), [ScoringBlocker.noLocation]);
  });

  test('a lookup that failed counts as no position', () async {
    final container = await containerWith(
      location: () async => throw StateError('no GPS'),
    );

    expect(await settled(container), [ScoringBlocker.noLocation]);
  });

  test('a position still on its way is not "no position"', () async {
    // Flashing a warning for the seconds a fix takes would teach a child
    // that the warning is noise.
    final container = await containerWith(
      location:
          () => Future<AppLocation?>.delayed(
            const Duration(seconds: 1),
            () => null,
          ),
    );

    expect(container.read(scoringBlockersProvider), isEmpty);
  });

  test('ordered by where the fix is: the plain page first', () async {
    // The live bar and the settings banner both list them in this order,
    // the plain page's fix first — so the order is part of the contract.
    final container = await containerWith(
      prefs: const {'species_filter_mode': 'off', 'confidence_threshold': 20},
      location: () async => null,
    );

    expect(await settled(container), [
      ScoringBlocker.noLocation,
      ScoringBlocker.speciesFilterOff,
      ScoringBlocker.thresholdBelowFloor,
    ]);
  });

  test('only the location is fixed on the plain page', () {
    expect(ScoringBlocker.noLocation.isAdvancedSetting, isFalse);
    expect(ScoringBlocker.speciesFilterOff.isAdvancedSetting, isTrue);
    expect(ScoringBlocker.thresholdBelowFloor.isAdvancedSetting, isTrue);
  });
}
