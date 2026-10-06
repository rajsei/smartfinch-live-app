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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sticker_board.dart';

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
    this.content = StickerBounds.whole,
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

  /// Where in the image the bird is — what the board keeps on the board
  /// (`StickerPlacement.keptOn`). Measured from the opaque pixels when the
  /// catalogue loads; the whole square until then, or if it cannot be.
  final StickerBounds content;

  Sticker withContent(StickerBounds content) => Sticker(
    id: id,
    scientificName: scientificName,
    imageAsset: imageAsset,
    names: names,
    content: content,
  );
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

    final catalog = StickerCatalog.parse(
      manifestJson: await bundle.loadString('$kStickerAssetDir/stickers.json'),
      factsJsonByLocale: facts,
      imageAssets: images,
    );

    // Where each bird sits in its square — measured, not authored, so a new
    // sticker needs no extra numbers. A dozen 512-pixel images, once.
    return StickerCatalog(
      stickers: [
        for (final sticker in catalog.stickers)
          sticker.withContent(await _measure(bundle, sticker.imageAsset)),
      ],
      facts: catalog.facts,
    );
  } catch (error) {
    debugPrint('[Stickers] could not load the catalogue: $error');
    return StickerCatalog.empty;
  }
}

/// Where the opaque pixels of an RGBA image are, as fractions of its size.
///
/// Pixels with an alpha of [threshold] or less count as empty — the faint
/// fringe of an antialiased edge is not the bird. An image with nothing in it
/// is taken to fill its square.
///
/// Scans inward from each side and stops at the first opaque pixel, so the
/// usual sticker costs a fraction of its pixels.
StickerBounds opaqueBounds(
  Uint8List rgba,
  int width,
  int height, {
  int threshold = 8,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return StickerBounds.whole;
  }
  bool opaque(int x, int y) => rgba[(y * width + x) * 4 + 3] > threshold;
  bool rowHas(int y) {
    for (var x = 0; x < width; x++) {
      if (opaque(x, y)) return true;
    }
    return false;
  }

  var top = 0;
  while (top < height && !rowHas(top)) {
    top++;
  }
  if (top == height) return StickerBounds.whole;
  var bottom = height - 1;
  while (bottom > top && !rowHas(bottom)) {
    bottom--;
  }

  bool columnHas(int x) {
    for (var y = top; y <= bottom; y++) {
      if (opaque(x, y)) return true;
    }
    return false;
  }

  var left = 0;
  while (left < width && !columnHas(left)) {
    left++;
  }
  var right = width - 1;
  while (right > left && !columnHas(right)) {
    right--;
  }

  return StickerBounds(
    left / width,
    top / height,
    (right + 1) / width,
    (bottom + 1) / height,
  );
}

/// The opaque area of the image at [asset], or the whole square if it cannot
/// be read — measuring is a refinement, never a reason to lose a sticker.
Future<StickerBounds> _measure(AssetBundle bundle, String asset) async {
  try {
    final data = await bundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bounds =
        pixels == null
            ? StickerBounds.whole
            : opaqueBounds(
              pixels.buffer.asUint8List(),
              image.width,
              image.height,
            );
    image.dispose();
    codec.dispose();
    return bounds;
  } catch (error) {
    debugPrint('[Stickers] could not measure $asset: $error');
    return StickerBounds.whole;
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
