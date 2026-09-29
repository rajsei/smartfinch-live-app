// =============================================================================
// The sticker catalogue — what can be picked, and what each bird is (AVA-07)
// =============================================================================
//
// Hand-drawn stickers live in `assets/stickers/`: a list (`stickers.json`),
// one image per sticker (`images/<id>.png|.webp`) and one fact file per
// language (`facts_<locale>.json`). See the `_readme` in `stickers.json` for
// how to add one.
//
// ### Tolerant on purpose
//
// The catalogue is authored by hand and grows over time, so a mistake in it
// must cost one sticker, never the home screen. An entry without an id, with
// a duplicate id, or without an image is skipped; a missing fact reads as no
// fact; a list that does not parse reads as no stickers at all.
//
// ### Names and facts come from different places
//
// A sticker's *name* follows the species-name language, like every other bird
// in the app: the entry's own `names` first (a child-friendly "Kiwi", or a
// bird BirdNET does not know), then the taxonomy, then English. Its *fact*
// follows the app language, because it is prose the child reads: that
// language's fact file, then English. A new language is a new fact file and
// nothing else — [loadStickerCatalog] finds it on its own.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the stickers live.
const String kStickerAssetDir = 'assets/stickers';

/// One sticker in the catalogue.
@immutable
class Sticker {
  const Sticker({
    required this.id,
    required this.scientificName,
    required this.imageAsset,
    this.names = const {},
  });

  /// Stable identifier: the scientific name in lower case with underscores.
  ///
  /// ⚠️ A child's saved picks refer to it. Never reused, never renamed.
  final String id;

  /// Links the sticker to the taxonomy for its common name.
  final String scientificName;

  /// The image, as an asset path.
  final String imageAsset;

  /// Names that win over the taxonomy, by locale.
  final Map<String, String> names;
}

/// All stickers, in album order, with their facts.
@immutable
class StickerCatalog {
  const StickerCatalog({required this.stickers, this.facts = const {}});

  /// No stickers — what a catalogue that failed to load looks like.
  static const StickerCatalog empty = StickerCatalog(stickers: []);

  /// In album order.
  final List<Sticker> stickers;

  /// Locale → sticker id → fact.
  final Map<String, Map<String, String>> facts;

  /// Builds a catalogue from the raw files.
  ///
  /// [manifestJson] is `stickers.json`, [factsJsonByLocale] maps a locale to
  /// the content of its fact file, and [imageAssets] lists the image paths
  /// that exist — an entry whose image is missing is skipped rather than
  /// shown as a blank.
  factory StickerCatalog.parse({
    required String manifestJson,
    Map<String, String> factsJsonByLocale = const {},
    required Set<String> imageAssets,
  }) {
    final stickers = <Sticker>[];
    final seen = <String>{};

    for (final entry in _entriesIn(manifestJson)) {
      final id = entry['id'];
      final scientificName = entry['scientificName'];
      if (id is! String || id.isEmpty || !seen.add(id)) continue;
      if (scientificName is! String || scientificName.isEmpty) continue;

      final image = _imageFor(id, imageAssets);
      if (image == null) continue;

      stickers.add(
        Sticker(
          id: id,
          scientificName: scientificName,
          imageAsset: image,
          names: _stringMap(entry['names']),
        ),
      );
    }

    return StickerCatalog(
      stickers: List.unmodifiable(stickers),
      facts: {
        for (final e in factsJsonByLocale.entries)
          _languageOf(e.key): _stringMap(_decodeOrNull(e.value)),
      },
    );
  }

  /// The sticker with [id], or null if the catalogue no longer has it.
  Sticker? byId(String id) {
    for (final sticker in stickers) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }

  /// The name to show for [sticker] in [locale].
  ///
  /// [taxonomyName] looks a scientific name up in the taxonomy for a locale;
  /// passed in rather than imported so this stays testable without assets.
  String nameFor(
    Sticker sticker,
    String locale, {
    String? Function(String scientificName, String locale)? taxonomyName,
  }) {
    final language = _languageOf(locale);

    final own = sticker.names[locale] ?? sticker.names[language];
    if (own != null && own.isNotEmpty) return own;

    final fromTaxonomy = taxonomyName?.call(sticker.scientificName, locale);
    if (fromTaxonomy != null && fromTaxonomy.isNotEmpty) return fromTaxonomy;

    final english = sticker.names['en'];
    if (english != null && english.isNotEmpty) return english;

    return sticker.scientificName;
  }

  /// The fact for sticker [id] in [locale], falling back to English.
  String? factFor(String id, String locale) {
    final fact = facts[_languageOf(locale)]?[id] ?? facts['en']?[id];
    return fact == null || fact.isEmpty ? null : fact;
  }
}

/// Loads the catalogue from [bundle], or [StickerCatalog.empty] on failure.
///
/// Fact files are discovered through the asset manifest, so adding a language
/// is dropping in `facts_<locale>.json` — no list to keep in step.
Future<StickerCatalog> loadStickerCatalog(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final assets = manifest.listAssets();

    final images = {
      for (final asset in assets)
        if (asset.startsWith('$kStickerAssetDir/images/')) asset,
    };

    final factFile = RegExp('^$kStickerAssetDir/facts_([A-Za-z_-]+)\\.json\$');
    final facts = <String, String>{};
    for (final asset in assets) {
      final match = factFile.firstMatch(asset);
      if (match == null) continue;
      facts[match.group(1)!] = await bundle.loadString(asset);
    }

    return StickerCatalog.parse(
      manifestJson: await bundle.loadString('$kStickerAssetDir/stickers.json'),
      factsJsonByLocale: facts,
      imageAssets: images,
    );
  } catch (error) {
    debugPrint('[Stickers] could not load the catalogue: $error');
    return StickerCatalog.empty;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

Iterable<Map<dynamic, dynamic>> _entriesIn(String manifestJson) sync* {
  final decoded = _decodeOrNull(manifestJson);
  if (decoded is! Map) return;
  final list = decoded['stickers'];
  if (list is! List) return;
  for (final entry in list) {
    if (entry is Map) yield entry;
  }
}

String? _imageFor(String id, Set<String> imageAssets) {
  for (final extension in const ['png', 'webp']) {
    final path = '$kStickerAssetDir/images/$id.$extension';
    if (imageAssets.contains(path)) return path;
  }
  return null;
}

Object? _decodeOrNull(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final e in value.entries)
      if (e.key is String &&
          !(e.key as String).startsWith('_') &&
          e.value is String)
        e.key as String: e.value as String,
  };
}

/// `de-DE`, `de_DE` and `de` all mean German here.
String _languageOf(String locale) =>
    locale.trim().replaceAll('_', '-').split('-').first.toLowerCase();
