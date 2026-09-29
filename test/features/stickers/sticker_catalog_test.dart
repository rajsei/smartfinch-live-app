// =============================================================================
// The sticker catalogue — AVA-07
// =============================================================================
//
// Two claims worth holding.
//
//   **A mistake in the hand-written catalogue costs one sticker, never the
//   home screen.** Bad entries are skipped, a list that does not parse is
//   empty.
//
//   **The shipped files agree with each other.** Every sticker has an image,
//   a German fact and an English fact — checked against the real assets, so
//   a sticker added without its fact fails here and not on a child's phone.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/stickers/sticker_catalog.dart';

void main() {
  String manifest(List<Object?> stickers) => jsonEncode({
    '_readme': ['ignored'],
    'stickers': stickers,
  });

  const images = {
    'assets/stickers/images/alcedo_atthis.png',
    'assets/stickers/images/balaeniceps_rex.webp',
    'assets/stickers/images/apteryx_mantelli.png',
  };

  group('parse', () {
    test('keeps the order of the list', () {
      final catalog = StickerCatalog.parse(
        manifestJson: manifest([
          {'id': 'balaeniceps_rex', 'scientificName': 'Balaeniceps rex'},
          {'id': 'alcedo_atthis', 'scientificName': 'Alcedo atthis'},
        ]),
        imageAssets: images,
      );

      expect(catalog.stickers.map((s) => s.id), [
        'balaeniceps_rex',
        'alcedo_atthis',
      ]);
    });

    test('finds a png or a webp image', () {
      final catalog = StickerCatalog.parse(
        manifestJson: manifest([
          {'id': 'alcedo_atthis', 'scientificName': 'Alcedo atthis'},
          {'id': 'balaeniceps_rex', 'scientificName': 'Balaeniceps rex'},
        ]),
        imageAssets: images,
      );

      expect(
        catalog.byId('alcedo_atthis')!.imageAsset,
        'assets/stickers/images/alcedo_atthis.png',
      );
      expect(
        catalog.byId('balaeniceps_rex')!.imageAsset,
        'assets/stickers/images/balaeniceps_rex.webp',
      );
    });

    test('skips entries it cannot use, and keeps the rest', () {
      final catalog = StickerCatalog.parse(
        manifestJson: manifest([
          {'id': 'alcedo_atthis', 'scientificName': 'Alcedo atthis'},
          {'id': 'alcedo_atthis', 'scientificName': 'Duplicate'},
          {'scientificName': 'No id'},
          {'id': 'apteryx_mantelli'},
          {'id': 'no_image', 'scientificName': 'Nowhere'},
          'not an object',
          {'id': 'balaeniceps_rex', 'scientificName': 'Balaeniceps rex'},
        ]),
        imageAssets: images,
      );

      expect(catalog.stickers.map((s) => s.id), [
        'alcedo_atthis',
        'balaeniceps_rex',
      ]);
      expect(catalog.byId('alcedo_atthis')!.scientificName, 'Alcedo atthis');
    });

    test('a list that does not parse is no stickers, not a crash', () {
      expect(
        StickerCatalog.parse(
          manifestJson: '{broken',
          imageAssets: images,
        ).stickers,
        isEmpty,
      );
      expect(
        StickerCatalog.parse(manifestJson: '[]', imageAssets: images).stickers,
        isEmpty,
      );
    });

    test('an unknown id is null', () {
      expect(StickerCatalog.empty.byId('alcedo_atthis'), isNull);
    });
  });

  group('names follow the species language', () {
    final catalog = StickerCatalog.parse(
      manifestJson: manifest([
        {'id': 'alcedo_atthis', 'scientificName': 'Alcedo atthis'},
        {
          'id': 'apteryx_mantelli',
          'scientificName': 'Apteryx mantelli',
          'names': {'de': 'Kiwi', 'en': 'Kiwi'},
        },
        {
          'id': 'balaeniceps_rex',
          'scientificName': 'Balaeniceps rex',
          'names': {'de': 'Schuhschnabel', 'en': 'Shoebill'},
        },
      ]),
      imageAssets: images,
    );

    String? taxonomy(String scientificName, String locale) => switch ((
      scientificName,
      locale,
    )) {
      ('Alcedo atthis', 'de') => 'Eisvogel',
      ('Alcedo atthis', _) => 'Common Kingfisher',
      ('Apteryx mantelli', 'de') => 'Nordstreifenkiwi',
      _ => null,
    };

    test('the taxonomy names a bird the list does not', () {
      final kingfisher = catalog.byId('alcedo_atthis')!;
      expect(
        catalog.nameFor(kingfisher, 'de', taxonomyName: taxonomy),
        'Eisvogel',
      );
    });

    test('the list wins over the taxonomy', () {
      final kiwi = catalog.byId('apteryx_mantelli')!;
      expect(catalog.nameFor(kiwi, 'de', taxonomyName: taxonomy), 'Kiwi');
    });

    test('a regional locale uses its language', () {
      final kiwi = catalog.byId('apteryx_mantelli')!;
      expect(catalog.nameFor(kiwi, 'de-AT', taxonomyName: taxonomy), 'Kiwi');
    });

    test('a bird the taxonomy does not know falls back to English', () {
      final shoebill = catalog.byId('balaeniceps_rex')!;
      expect(
        catalog.nameFor(shoebill, 'fr', taxonomyName: taxonomy),
        'Shoebill',
      );
    });

    test('and with no name anywhere, the scientific name', () {
      const bare = Sticker(
        id: 'x',
        scientificName: 'Avis ignota',
        imageAsset: 'x.png',
      );
      expect(catalog.nameFor(bare, 'de'), 'Avis ignota');
    });
  });

  group('facts follow the app language', () {
    final catalog = StickerCatalog.parse(
      manifestJson: manifest([
        {'id': 'alcedo_atthis', 'scientificName': 'Alcedo atthis'},
      ]),
      factsJsonByLocale: {
        'de': jsonEncode({'alcedo_atthis': 'Deutsch'}),
        'en': jsonEncode({'alcedo_atthis': 'English'}),
        'fr': '{broken',
      },
      imageAssets: images,
    );

    test('in the language asked for', () {
      expect(catalog.factFor('alcedo_atthis', 'de'), 'Deutsch');
      expect(catalog.factFor('alcedo_atthis', 'de_CH'), 'Deutsch');
    });

    test('in English where the language has none', () {
      expect(catalog.factFor('alcedo_atthis', 'it'), 'English');
      expect(catalog.factFor('alcedo_atthis', 'fr'), 'English');
    });

    test('and none for a sticker without a fact', () {
      expect(catalog.factFor('unknown', 'de'), isNull);
    });
  });

  group('⚠️ the shipped stickers', () {
    Map<String, dynamic> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    final entries =
        (read('assets/stickers/stickers.json')['stickers'] as List)
            .cast<Map<String, dynamic>>();
    final ids = [for (final e in entries) e['id'] as String];

    test('ids are unique scientific names in lower case', () {
      expect(ids.toSet(), hasLength(ids.length));
      for (final entry in entries) {
        final expected = (entry['scientificName'] as String)
            .toLowerCase()
            .replaceAll(' ', '_');
        expect(entry['id'], expected);
      }
    });

    test('every sticker has an image', () {
      for (final id in ids) {
        final png = File('assets/stickers/images/$id.png').existsSync();
        final webp = File('assets/stickers/images/$id.webp').existsSync();
        expect(png || webp, isTrue, reason: '$id has no image');
      }
    });

    test('every sticker has a German and an English fact', () {
      for (final locale in ['de', 'en']) {
        final facts = read('assets/stickers/facts_$locale.json');
        for (final id in ids) {
          expect(
            facts[id],
            isA<String>().having((f) => f.trim(), 'text', isNotEmpty),
            reason: '$id has no $locale fact',
          );
        }
        expect(
          facts.keys.where((k) => !k.startsWith('_')).toSet(),
          ids.toSet(),
          reason: 'facts_$locale.json has facts for stickers that do not exist',
        );
      }
    });

    test('and they parse as a catalogue with nothing skipped', () {
      final images = {
        for (final f in Directory('assets/stickers/images').listSync())
          f.path.replaceAll('\\', '/'),
      };
      final catalog = StickerCatalog.parse(
        manifestJson: File('assets/stickers/stickers.json').readAsStringSync(),
        imageAssets: images,
      );
      expect(catalog.stickers.map((s) => s.id), ids);
    });
  });
}
