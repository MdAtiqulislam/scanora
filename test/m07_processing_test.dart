import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:scanora/app/core/errors/app_failure.dart';
import 'package:scanora/app/core/errors/processing_failure.dart';
import 'package:scanora/app/core/result/result.dart';
import 'package:scanora/app/domain/contracts/asset_store.dart';
import 'package:scanora/app/domain/entities/scan_page.dart';
import 'package:scanora/app/domain/geometry/geometry_models.dart';
import 'package:scanora/app/domain/processing/processing_models.dart';
import 'package:scanora/app/domain/value_objects/page_corners.dart';
import 'package:scanora/app/domain/value_objects/point.dart';
import 'package:scanora/app/domain/value_objects/processing_profile.dart';
import 'package:scanora/app/domain/enums/scan_enums.dart';
import 'package:scanora/app/infrastructure/processing/m07_processing_engine.dart';
import 'package:scanora/app/infrastructure/processing/plain_geometry_engine.dart';

class MemoryAssets implements AssetStore {
  final raw = <String, List<int>>{
    'doc/page': img.encodeJpg(img.Image(width: 8, height: 8)),
  };
  final processed = <String, List<int>>{};
  final thumbnails = <String, List<int>>{};
  int rawReads = 0;
  int processedReads = 0;
  int thumbnailReads = 0;
  int processedWrites = 0;
  int thumbnailWrites = 0;
  bool failSaveProcessed = false;
  bool failSaveThumbnail = false;
  Future<void> Function(String d, String p)? onBeforeReadRaw;

  String key(String doc, String page) => '$doc/$page';

  @override
  Future<Result<String>> saveProcessedImage(
    String d,
    String p,
    List<int> b,
  ) async {
    if (failSaveProcessed) {
      return const Failure(
        StorageFailure('Simulated saveProcessedImage failure'),
      );
    }
    processed[key(d, p)] = [...b];
    processedWrites++;
    return Success('processed/$d/$p');
  }

  @override
  Future<Result<String>> saveThumbnail(String d, String p, List<int> b) async {
    if (failSaveThumbnail) {
      return const Failure(
        StorageFailure('Simulated saveThumbnail failure'),
      );
    }
    thumbnails[key(d, p)] = [...b];
    thumbnailWrites++;
    return Success('thumbnail/$d/$p');
  }

  @override
  Future<Result<List<int>>> readRawImage(String d, String p) async {
    if (onBeforeReadRaw != null) {
      await onBeforeReadRaw!(d, p);
    }
    rawReads++;
    return Success(raw[key(d, p)] ?? []);
  }

  @override
  Future<Result<String>> createDocumentStorage(String id) async => Success(id);
  @override
  Future<Result<String>> createPageStorage(String d, String p) async =>
      Success('$d/$p');
  @override
  Future<Result<String>> saveRawImage(String d, String p, List<int> b) async =>
      Success('raw/$d/$p');
  @override
  Future<Result<List<int>>> readProcessedImage(String d, String p) async {
    processedReads++;
    return Success(processed[key(d, p)] ?? []);
  }

  @override
  Future<Result<List<int>>> readThumbnail(String d, String p) async {
    thumbnailReads++;
    return Success(thumbnails[key(d, p)] ?? []);
  }

  @override
  Future<Result<bool>> exists(String d, String p, AssetKind k) async =>
      Success(switch (k) {
        AssetKind.raw => raw.containsKey(key(d, p)),
        AssetKind.processed => processed.containsKey(key(d, p)),
        AssetKind.thumbnail => thumbnails.containsKey(key(d, p)),
      });
  @override
  Future<Result<String>> pathFor(String d, String p, AssetKind k) async =>
      Success('${k.name}/$d/$p');
  @override
  Future<Result<void>> deletePageAssets(String d, String p) async =>
      const Success(null);
  @override
  Future<Result<void>> deleteDocumentAssets(String d) async =>
      const Success(null);
  @override
  Future<Result<AssetIntegrityReport>> inspectIntegrity({
    required Iterable<String> documentIds,
    required Iterable<({String documentId, String pageId})> pages,
    required Iterable<({String documentId, String pageId, AssetKind kind})>
    referencedAssets,
  }) async => const Success(AssetIntegrityReport());
}

void main() {
  final corners = PageCorners(
    topLeft: const Point2D(0, 0),
    topRight: const Point2D(1, 0),
    bottomRight: const Point2D(1, 1),
    bottomLeft: const Point2D(0, 1),
  );
  final page = ScanPage(
    id: 'page',
    documentId: 'doc',
    pageIndex: 0,
    corners: corners,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  ProcessingRequest request(ScanPage value) => ProcessingRequest(
    documentId: 'doc',
    pageId: 'page',
    rawAssetIdentity: 'raw-v1',
    editState: PageEditStateSnapshot(value),
    sourceSize: const PixelSize(1000, 1000),
  );

  test(
    'M07 processes sequentially from raw and produces derived assets',
    () async {
      final assets = MemoryAssets();
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      final before = [...assets.raw['doc/page']!];
      final result = await engine.process(request(page));
      expect(result, isA<Success<ProcessingResult>>());
      expect(assets.raw['doc/page'], before);
      expect(assets.processed['doc/page'], isNot(equals(before)));
      expect(assets.thumbnails['doc/page'], isNot(equals(before)));
    },
  );

  test(
    'same request is deterministic and raw identity changes cache identity',
    () async {
      final assets = MemoryAssets();
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      final first =
          (await engine.process(request(page)) as Success<ProcessingResult>)
              .value;
      final second =
          (await engine.process(request(page)) as Success<ProcessingResult>)
              .value;
      expect(first.plan.processedCacheKey, second.plan.processedCacheKey);
      expect(first.plan.thumbnailCacheKey, second.plan.thumbnailCacheKey);
      final changed =
          (await engine.process(request(page).copyWithRaw('raw-v2'))
                  as Success<ProcessingResult>)
              .value;
      expect(
        changed.plan.processedCacheKey,
        isNot(first.plan.processedCacheKey),
      );
    },
  );

  test(
    'unsupported profiles and cancellation fail without derived outputs',
    () async {
      final assets = MemoryAssets();
      var cancelled = true;
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        isCancelled: () => cancelled,
      );
      expect(
        await engine.process(request(page)),
        isA<Failure<ProcessingResult>>(),
      );
      cancelled = false;
      final unsupported = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        processingProfile: const ProcessingProfile(
          filterType: ScanFilterType.magic,
        ),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(
        await engine.process(request(unsupported)),
        isA<Failure<ProcessingResult>>(),
      );
      expect(assets.processed, isEmpty);
    },
  );

  test('pixel rendering and thumbnail bounds are real', () async {
    final source = img.Image(width: 40, height: 20);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 6, y * 12, 40);
      }
    }
    final assets = MemoryAssets()..raw['doc/page'] = img.encodeJpg(source);
    final pixelRequest = ProcessingRequest(
      documentId: 'doc',
      pageId: 'page',
      rawAssetIdentity: 'raw-v1',
      editState: PageEditStateSnapshot(page),
      sourceSize: const PixelSize(40, 20),
    );
    final result =
        (await M07ProcessingEngine(
              assets: assets,
              geometry: const PlainGeometryEngine(),
            ).process(pixelRequest))
            as Success<ProcessingResult>;
    final processed =
        img.decodeImage(Uint8List.fromList(assets.processed['doc/page']!))!;
    final thumbnail =
        img.decodeImage(Uint8List.fromList(assets.thumbnails['doc/page']!))!;
    expect(processed.width, 40);
    expect(processed.height, 20);
    expect(thumbnail.width, lessThanOrEqualTo(320));
    expect(thumbnail.height, lessThanOrEqualTo(320));
    expect(assets.processed['doc/page'], isNot(equals(assets.raw['doc/page'])));
    expect(result.value.plan.processedCacheKey, isNotEmpty);
  });

  test(
    'fifty requests execute sequentially through the same bounded path',
    () async {
      final assets = MemoryAssets();
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      for (var i = 0; i < 50; i++) {
        final id = 'page-$i';
        assets.raw['doc/$id'] = assets.raw['doc/page']!;
        final value = ScanPage(
          id: id,
          documentId: 'doc',
          pageIndex: i,
          corners: corners,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final result = await engine.process(
          ProcessingRequest(
            documentId: 'doc',
            pageId: id,
            rawAssetIdentity: 'raw-$i',
            editState: PageEditStateSnapshot(value),
            sourceSize: const PixelSize(8, 8),
          ),
        );
        expect(result, isA<Success<ProcessingResult>>());
      }
      expect(assets.processedWrites, 50);
      expect(assets.thumbnailWrites, 50);
    },
  );
  img.Image createAsymmetricTestImage(int width, int height) {
    final image = img.Image(width: width, height: height);
    // Fill background with dark gray
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, 30, 30, 30);
      }
    }
    // Draw distinct 3x3 corner color markers
    // Top-Left: Red
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        image.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    // Top-Right: Green
    for (var y = 0; y < 3; y++) {
      for (var x = width - 3; x < width; x++) {
        image.setPixelRgb(x, y, 0, 255, 0);
      }
    }
    // Bottom-Right: Blue
    for (var y = height - 3; y < height; y++) {
      for (var x = width - 3; x < width; x++) {
        image.setPixelRgb(x, y, 0, 0, 255);
      }
    }
    // Bottom-Left: Yellow
    for (var y = height - 3; y < height; y++) {
      for (var x = 0; x < 3; x++) {
        image.setPixelRgb(x, y, 255, 255, 0);
      }
    }
    return image;
  }

  bool isRed(img.Pixel p) => p.r > 180 && p.g < 70 && p.b < 70;
  bool isGreen(img.Pixel p) => p.g > 180 && p.r < 70 && p.b < 70;
  bool isBlue(img.Pixel p) => p.b > 180 && p.r < 70 && p.g < 70;
  bool isYellow(img.Pixel p) => p.r > 180 && p.g > 180 && p.b < 70;

  test('authoritative raster rotation renders 0, 90, 180, and 270 degrees clockwise', () async {
    final testImage = createAsymmetricTestImage(40, 20);
    final encodedRaw = img.encodeJpg(testImage);

    for (final angle in [0, 90, 180, 270]) {
      final assets = MemoryAssets()..raw['doc/page-$angle'] = [...encodedRaw];
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      final pageWithRotation = ScanPage(
        id: 'page-$angle',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        rotationAngle: angle.toDouble(),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final req = ProcessingRequest(
        documentId: 'doc',
        pageId: 'page-$angle',
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(pageWithRotation),
        sourceSize: const PixelSize(40, 20),
      );

      final result = await engine.process(req);
      expect(result, isA<Success<ProcessingResult>>());

      final processedBytes = assets.processed['doc/page-$angle']!;
      final processedImage = img.decodeImage(Uint8List.fromList(processedBytes))!;

      // Sample center of 3x3 corner patches (offset by 1 pixel from border)
      final tl = processedImage.getPixel(1, 1);
      final tr = processedImage.getPixel(processedImage.width - 2, 1);
      final br = processedImage.getPixel(processedImage.width - 2, processedImage.height - 2);
      final bl = processedImage.getPixel(1, processedImage.height - 2);

      switch (angle) {
        case 0:
          expect(processedImage.width, 40);
          expect(processedImage.height, 20);
          expect(isRed(tl), isTrue, reason: '0 deg TL must be Red');
          expect(isGreen(tr), isTrue, reason: '0 deg TR must be Green');
          expect(isBlue(br), isTrue, reason: '0 deg BR must be Blue');
          expect(isYellow(bl), isTrue, reason: '0 deg BL must be Yellow');
        case 90:
          expect(processedImage.width, 20);
          expect(processedImage.height, 40);
          expect(isYellow(tl), isTrue, reason: '90 deg TL must be Yellow (from BL)');
          expect(isRed(tr), isTrue, reason: '90 deg TR must be Red (from TL)');
          expect(isGreen(br), isTrue, reason: '90 deg BR must be Green (from TR)');
          expect(isBlue(bl), isTrue, reason: '90 deg BL must be Blue (from BR)');
        case 180:
          expect(processedImage.width, 40);
          expect(processedImage.height, 20);
          expect(isBlue(tl), isTrue, reason: '180 deg TL must be Blue (from BR)');
          expect(isYellow(tr), isTrue, reason: '180 deg TR must be Yellow (from BL)');
          expect(isRed(br), isTrue, reason: '180 deg BR must be Red (from TL)');
          expect(isGreen(bl), isTrue, reason: '180 deg BL must be Green (from TR)');
        case 270:
          expect(processedImage.width, 20);
          expect(processedImage.height, 40);
          expect(isGreen(tl), isTrue, reason: '270 deg TL must be Green (from TR)');
          expect(isBlue(tr), isTrue, reason: '270 deg TR must be Blue (from BR)');
          expect(isYellow(br), isTrue, reason: '270 deg BR must be Yellow (from BL)');
          expect(isRed(bl), isTrue, reason: '270 deg BL must be Red (from TL)');
      }
    }
  });

  test('raster and thumbnail dimensions swap orientation under 90 and 270 degrees', () async {
    final testImage = createAsymmetricTestImage(60, 30);
    final encodedRaw = img.encodeJpg(testImage);

    for (final angle in [0, 90, 180, 270]) {
      final assets = MemoryAssets()..raw['doc/dim-$angle'] = [...encodedRaw];
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      final pageWithRotation = ScanPage(
        id: 'dim-$angle',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        rotationAngle: angle.toDouble(),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final req = ProcessingRequest(
        documentId: 'doc',
        pageId: 'dim-$angle',
        rawAssetIdentity: 'raw-dim',
        editState: PageEditStateSnapshot(pageWithRotation),
        sourceSize: const PixelSize(60, 30),
      );

      final result = await engine.process(req);
      expect(result, isA<Success<ProcessingResult>>());

      final processed = img.decodeImage(Uint8List.fromList(assets.processed['doc/dim-$angle']!))!;
      final thumbnail = img.decodeImage(Uint8List.fromList(assets.thumbnails['doc/dim-$angle']!))!;

      if (angle == 0 || angle == 180) {
        expect(processed.width, 60);
        expect(processed.height, 30);
        expect(thumbnail.width, greaterThan(thumbnail.height));
      } else {
        expect(processed.width, 30);
        expect(processed.height, 60);
        expect(thumbnail.height, greaterThan(thumbnail.width));
      }
    }
  });

  test('asymmetric perspective quadrilateral processes and rotates correctly across all angles', () async {
    final testImage = createAsymmetricTestImage(200, 100);
    final encodedRaw = img.encodeJpg(testImage);
    final asymmetricCorners = PageCorners(
      topLeft: const Point2D(0.10, 0.05),
      topRight: const Point2D(0.90, 0.10),
      bottomRight: const Point2D(0.95, 0.95),
      bottomLeft: const Point2D(0.05, 0.90),
    );

    const geometryEngine = PlainGeometryEngine();
    final geom = (geometryEngine.calculate(
      corners: asymmetricCorners,
      sourceSize: const PixelSize(200, 100),
      rotationDegrees: 0,
    ) as Success<GeometryResult>).value;

    final baseWidth = geom.destinationSize.width;
    final baseHeight = geom.destinationSize.height;

    for (final angle in [0, 90, 180, 270]) {
      final assets = MemoryAssets()..raw['doc/quad-$angle'] = [...encodedRaw];
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: geometryEngine,
      );
      final pageWithQuad = ScanPage(
        id: 'quad-$angle',
        documentId: 'doc',
        pageIndex: 0,
        corners: asymmetricCorners,
        rotationAngle: angle.toDouble(),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final req = ProcessingRequest(
        documentId: 'doc',
        pageId: 'quad-$angle',
        rawAssetIdentity: 'raw-quad',
        editState: PageEditStateSnapshot(pageWithQuad),
        sourceSize: const PixelSize(200, 100),
      );

      final result = await engine.process(req);
      expect(result, isA<Success<ProcessingResult>>());

      final processed = img.decodeImage(Uint8List.fromList(assets.processed['doc/quad-$angle']!))!;
      if (angle == 0 || angle == 180) {
        expect(processed.width, baseWidth);
        expect(processed.height, baseHeight);
      } else {
        expect(processed.width, baseHeight);
        expect(processed.height, baseWidth);
      }
    }
  });

  test('raw image asset bytes are strictly immutable across all rotation angles', () async {
    final testImage = createAsymmetricTestImage(40, 20);
    final encodedRaw = img.encodeJpg(testImage);

    for (final angle in [0, 90, 180, 270]) {
      final rawCopy = [...encodedRaw];
      final assets = MemoryAssets()..raw['doc/raw-$angle'] = rawCopy;
      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );
      final pageWithRotation = ScanPage(
        id: 'raw-$angle',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        rotationAngle: angle.toDouble(),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final req = ProcessingRequest(
        documentId: 'doc',
        pageId: 'raw-$angle',
        rawAssetIdentity: 'raw-immutability',
        editState: PageEditStateSnapshot(pageWithRotation),
        sourceSize: const PixelSize(40, 20),
      );

      final result = await engine.process(req);
      expect(result, isA<Success<ProcessingResult>>());

      expect(
        assets.raw['doc/raw-$angle'],
        equals(encodedRaw),
        reason: 'Raw asset bytes must not be mutated for rotation angle $angle',
      );
    }
  });

  group('M07-FIX-02 Unified Cache Identity and Real Cache HIT', () {
    test('Test 1 — true cache HIT reuses assets without decoding, rendering, encoding, or reading raw image', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      var decodeCount = 0;
      var renderCount = 0;
      var encodeCount = 0;

      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      M07ProcessingEngine createEngine() {
        return M07ProcessingEngine(
          assets: assets,
          geometry: const PlainGeometryEngine(),
          markCacheCurrent: ({
            required pageId,
            required processedCacheKey,
            required thumbnailCacheKey,
            required expectedRawAssetIdentity,
            required expectedEditState,
          }) async {
            pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
            return const Success(null);
          },
          decodeImageSeam: (bytes) {
            decodeCount++;
            return img.decodeImage(bytes);
          },
          renderGeometrySeam: (source, geom) {
            renderCount++;
            return const PlainGeometryEngine().canonicalize([
              const Point2D(0, 0),
              const Point2D(1, 0),
              const Point2D(1, 1),
              const Point2D(0, 1),
            ]).isSuccess
                ? img.copyResize(source, width: geom.destinationSize.width, height: geom.destinationSize.height)
                : source;
          },
          encodeJpgSeam: (image, {required quality}) {
            encodeCount++;
            return Uint8List.fromList(img.encodeJpg(image, quality: quality));
          },
        );
      }

      final engine = createEngine();

      // First call: full processing from raw
      final result1 = await engine.process(request(page));
      expect(result1, isA<Success<ProcessingResult>>());
      final res1 = (result1 as Success<ProcessingResult>).value;

      expect(assets.rawReads, 1, reason: 'First call reads raw asset once');
      expect(decodeCount, 1, reason: 'First call decodes raw asset once');
      expect(renderCount, 1, reason: 'First call renders geometry once');
      expect(encodeCount, 2, reason: 'First call encodes processed JPEG and thumbnail');
      expect(assets.processedWrites, 1);
      expect(assets.thumbnailWrites, 1);
      expect(pageKeys['page'], isNotNull);

      final persistedPKey = pageKeys['page']!.processedKey;
      final persistedTKey = pageKeys['page']!.thumbnailKey;
      expect(persistedPKey, res1.plan.processedCacheKey);
      expect(persistedTKey, res1.plan.thumbnailCacheKey);

      // Construct second request with persisted cache keys reflected in page
      final cachedPage = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        processedCacheKey: persistedPKey,
        thumbnailCacheKey: persistedTKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      // Second call: true cache HIT
      final result2 = await engine.process(request(cachedPage));
      expect(result2, isA<Success<ProcessingResult>>());
      final res2 = (result2 as Success<ProcessingResult>).value;

      expect(assets.rawReads, 1, reason: 'Cache HIT must NOT read raw asset');
      expect(decodeCount, 1, reason: 'Cache HIT must NOT decode raw asset');
      expect(renderCount, 1, reason: 'Cache HIT must NOT render geometry');
      expect(encodeCount, 2, reason: 'Cache HIT must NOT encode any JPEG');
      expect(assets.processedWrites, 1, reason: 'Cache HIT must NOT overwrite processed asset');
      expect(assets.thumbnailWrites, 1, reason: 'Cache HIT must NOT overwrite thumbnail asset');

      expect(res2.processedPath, res1.processedPath);
      expect(res2.thumbnailPath, res1.thumbnailPath);
      expect(assets.raw['doc/page'], equals(rawBefore), reason: 'Raw asset immutability');
    });

    test('Test 2 — processed cache remains reusable when thumbnail specification changes', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      // Request 1: 320x320, quality 85
      const thumbSpec1 = ThumbnailSpecification(width: 320, height: 320, quality: 85);
      final req1 = ProcessingRequest(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(page),
        sourceSize: const PixelSize(1000, 1000),
        thumbnail: thumbSpec1,
      );

      final result1 = (await engine.process(req1) as Success<ProcessingResult>).value;
      expect(assets.processedWrites, 1);
      expect(assets.thumbnailWrites, 1);
      expect(assets.rawReads, 1);

      final keyP1 = result1.plan.processedCacheKey;
      final keyT1 = result1.plan.thumbnailCacheKey;
      expect(pageKeys['page']!.processedKey, keyP1);
      expect(pageKeys['page']!.thumbnailKey, keyT1);

      // Request 2: same raw & edit state, but 512x512, quality 90
      const thumbSpec2 = ThumbnailSpecification(width: 512, height: 512, quality: 90);
      final pageWithKey1 = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        processedCacheKey: keyP1,
        thumbnailCacheKey: keyT1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final req2 = ProcessingRequest(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(pageWithKey1),
        sourceSize: const PixelSize(1000, 1000),
        thumbnail: thumbSpec2,
      );

      final result2 = (await engine.process(req2) as Success<ProcessingResult>).value;

      // Invariant: processed cache key MUST be identical
      expect(result2.plan.processedCacheKey, equals(keyP1),
          reason: 'ProcessedCacheKey must NOT depend on thumbnail specification');
      // Invariant: thumbnail cache key MUST differ
      expect(result2.plan.thumbnailCacheKey, isNot(equals(keyT1)),
          reason: 'ThumbnailCacheKey must change when thumbnail spec changes');

      // Processed JPEG was NOT regenerated!
      expect(assets.processedWrites, 1, reason: 'Processed asset must be reused, not regenerated');
      // Raw asset was NOT read!
      expect(assets.rawReads, 1, reason: 'Raw asset must not be re-read on partial cache hit');
      // Thumbnail was regenerated!
      expect(assets.thumbnailWrites, 2, reason: 'Thumbnail must be regenerated for new spec');
      expect(assets.processedReads, 1, reason: 'Existing processed image was read to generate thumbnail');

      expect(assets.raw['doc/page'], equals(rawBefore), reason: 'Raw asset immutability');
    });

    test('Test 3 — thumbnail cache invalidation triggers partial cache reuse across varying thumbnail specs', () async {
      final assets = MemoryAssets();
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      // Baseline
      final req1 = request(page);
      final res1 = (await engine.process(req1) as Success<ProcessingResult>).value;
      final pKey = res1.plan.processedCacheKey;

      // Varying width, height, quality
      for (final spec in [
        const ThumbnailSpecification(width: 160, height: 160, quality: 70),
        const ThumbnailSpecification(width: 200, height: 300, quality: 80),
        const ThumbnailSpecification(width: 200, height: 300, quality: 95),
      ]) {
        final cachedPage = ScanPage(
          id: 'page',
          documentId: 'doc',
          pageIndex: 0,
          corners: corners,
          processedCacheKey: pKey,
          thumbnailCacheKey: pageKeys['page']!.thumbnailKey,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final req = ProcessingRequest(
          documentId: 'doc',
          pageId: 'page',
          rawAssetIdentity: 'raw-v1',
          editState: PageEditStateSnapshot(cachedPage),
          sourceSize: const PixelSize(1000, 1000),
          thumbnail: spec,
        );

        final writesBefore = assets.processedWrites;
        final thumbWritesBefore = assets.thumbnailWrites;

        final res = (await engine.process(req) as Success<ProcessingResult>).value;

        expect(res.plan.processedCacheKey, equals(pKey));
        expect(assets.processedWrites, writesBefore, reason: 'Processed cache must HIT');
        expect(assets.thumbnailWrites, thumbWritesBefore + 1, reason: 'Thumbnail cache must MISS and regenerate');
      }
    });

    test('Test 4 — edit state changes invalidate both processed and thumbnail caches', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      final res1 = (await engine.process(request(page)) as Success<ProcessingResult>).value;
      final pKey1 = res1.plan.processedCacheKey;
      final tKey1 = res1.plan.thumbnailCacheKey;

      // Edit rotation: 90
      final rotatedPage = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        rotationAngle: 90,
        processedCacheKey: pKey1,
        thumbnailCacheKey: tKey1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final writesBefore = assets.processedWrites;
      final thumbWritesBefore = assets.thumbnailWrites;

      final res2 = (await engine.process(request(rotatedPage)) as Success<ProcessingResult>).value;

      expect(res2.plan.processedCacheKey, isNot(equals(pKey1)));
      expect(res2.plan.thumbnailCacheKey, isNot(equals(tKey1)));
      expect(assets.processedWrites, writesBefore + 1, reason: 'Processed asset must be regenerated');
      expect(assets.thumbnailWrites, thumbWritesBefore + 1, reason: 'Thumbnail asset must be regenerated');
      expect(assets.raw['doc/page'], equals(rawBefore));
    });

    test('Test 5 — raw asset identity change invalidates both processed and thumbnail caches', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      final res1 = (await engine.process(request(page)) as Success<ProcessingResult>).value;
      final pKey1 = res1.plan.processedCacheKey;
      final tKey1 = res1.plan.thumbnailCacheKey;

      final cachedPage = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        processedCacheKey: pKey1,
        thumbnailCacheKey: tKey1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final writesBefore = assets.processedWrites;
      final thumbWritesBefore = assets.thumbnailWrites;

      // Same page edit state, but different rawAssetIdentity
      final res2 = (await engine.process(request(cachedPage).copyWithRaw('raw-v2')) as Success<ProcessingResult>).value;

      expect(res2.plan.processedCacheKey, isNot(equals(pKey1)));
      expect(res2.plan.thumbnailCacheKey, isNot(equals(tKey1)));
      expect(assets.processedWrites, writesBefore + 1);
      expect(assets.thumbnailWrites, thumbWritesBefore + 1);
      expect(assets.raw['doc/page'], equals(rawBefore));
    });

    test('Test 6 — forceReprocess bypasses cache HIT and regenerates all derived assets', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      final res1 = (await engine.process(request(page)) as Success<ProcessingResult>).value;

      final cachedPage = ScanPage(
        id: 'page',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        processedCacheKey: res1.plan.processedCacheKey,
        thumbnailCacheKey: res1.plan.thumbnailCacheKey,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      // Call with forceReprocess: true
      final reqForce = ProcessingRequest(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(cachedPage),
        sourceSize: const PixelSize(1000, 1000),
        forceReprocess: true,
      );

      final writesBefore = assets.processedWrites;
      final thumbWritesBefore = assets.thumbnailWrites;

      final res2 = (await engine.process(reqForce) as Success<ProcessingResult>).value;

      expect(assets.processedWrites, writesBefore + 1, reason: 'forceReprocess must re-save processed asset');
      expect(assets.thumbnailWrites, thumbWritesBefore + 1, reason: 'forceReprocess must re-save thumbnail');
      expect(res2.plan.processedCacheKey, res1.plan.processedCacheKey);
      expect(res2.plan.thumbnailCacheKey, res1.plan.thumbnailCacheKey);
      expect(assets.raw['doc/page'], equals(rawBefore));
    });

    test('Test 7 — partial failure in thumbnail save prevents cache state from becoming current', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      assets.failSaveThumbnail = true;

      final resultFail = await engine.process(request(page));
      expect(resultFail, isA<Failure<ProcessingResult>>());
      expect((resultFail as Failure).error, isA<ProcessingPersistenceFailure>());

      // Cache state must NOT have become current
      expect(pageKeys['page'], isNull, reason: 'Failed thumbnail save must not update cache keys');

      // Next request with failure cleared
      assets.failSaveThumbnail = false;
      final resultRetry = await engine.process(request(page));
      expect(resultRetry, isA<Success<ProcessingResult>>());
      expect(pageKeys['page'], isNotNull, reason: 'Retry must succeed and update cache');
      expect(assets.raw['doc/page'], equals(rawBefore));
    });

    test('Test 8 — cache persistence failure prevents false cache HIT on subsequent requests', () async {
      final assets = MemoryAssets();
      final rawBefore = [...assets.raw['doc/page']!];
      var failPersistence = true;
      final pageKeys = <String, ({String? processedKey, String? thumbnailKey})>{};

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          if (failPersistence) {
            return const Failure(StorageFailure('Simulated database failure during cache update'));
          }
          pageKeys[pageId] = (processedKey: processedCacheKey, thumbnailKey: thumbnailCacheKey);
          return const Success(null);
        },
      );

      // Call fails during markCacheCurrent
      final resultFail = await engine.process(request(page));
      expect(resultFail, isA<Failure<ProcessingResult>>());
      expect((resultFail as Failure).error, isA<ProcessingPersistenceFailure>());

      // Both derived files were written to disk, but cache keys were NOT marked in DB
      expect(assets.processed.isNotEmpty, isTrue);
      expect(assets.thumbnails.isNotEmpty, isTrue);
      expect(pageKeys['page'], isNull, reason: 'Database was not updated');

      // Subsequent call with unmodified page (no cache keys) safely reprocesses without false HIT
      failPersistence = false;
      final writesBefore = assets.processedWrites;
      final resultRetry = await engine.process(request(page));
      expect(resultRetry, isA<Success<ProcessingResult>>());
      expect(assets.processedWrites, writesBefore + 1, reason: 'Must reprocess because cache was never current');
      expect(pageKeys['page'], isNotNull);
      expect(assets.raw['doc/page'], equals(rawBefore));
    });
  });

  group('M07-FIX-03 Bounded Processing, Memory Safety & Concurrency Isolation', () {
    test('Test 1 — FIFO execution order serializes queued heavy raster work strictly one at a time', () async {
      final assets = MemoryAssets();
      for (final id in ['pageA', 'pageB', 'pageC', 'pageD']) {
        assets.raw['doc/$id'] = img.encodeJpg(img.Image(width: 8, height: 8));
      }

      final aStarted = Completer<void>();
      final aRelease = Completer<void>();
      final executionOrder = <String>[];

      assets.onBeforeReadRaw = (doc, pageId) async {
        if (pageId == 'pageA') {
          if (!aStarted.isCompleted) aStarted.complete();
          await aRelease.future;
        }
      };

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );

      ScanPage createPage(String id) => ScanPage(
        id: id,
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      ProcessingRequest req(String id) => ProcessingRequest(
        documentId: 'doc',
        pageId: id,
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(createPage(id)),
        sourceSize: const PixelSize(1000, 1000),
      );

      // Start A — it will acquire the lock and pause at onBeforeReadRaw
      final futureA = engine.process(req('pageA')).then((res) {
        executionOrder.add('A');
        return res;
      });

      // Wait until A has acquired lock and paused
      await aStarted.future;
      expect(engine.activeHeavyJobs, equals(1));
      expect(engine.maximumObservedHeavyJobs, equals(1));

      // Enqueue B, C, D in FIFO order while A is paused
      final futureB = engine.process(req('pageB')).then((res) {
        executionOrder.add('B');
        return res;
      });
      final futureC = engine.process(req('pageC')).then((res) {
        executionOrder.add('C');
        return res;
      });
      final futureD = engine.process(req('pageD')).then((res) {
        executionOrder.add('D');
        return res;
      });

      // Release A to proceed
      aRelease.complete();

      final results = await Future.wait([futureA, futureB, futureC, futureD]);
      for (final r in results) {
        expect(r.isSuccess, isTrue);
      }

      expect(executionOrder, equals(['A', 'B', 'C', 'D']),
          reason: 'Queued jobs must complete strictly in FIFO arrival order');
      expect(engine.maximumObservedHeavyJobs, equals(1),
          reason: 'At no point may concurrent heavy jobs exceed 1');
      expect(engine.activeHeavyJobs, equals(0));
    });

    test('Test 2 — same-page concurrent race: only 1 does heavy work, 2 reuse cache post-queue', () async {
      final assets = MemoryAssets();
      var decodeCount = 0;
      var renderCount = 0;
      var encodeCount = 0;

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        decodeImageSeam: (bytes) {
          decodeCount++;
          return img.decodeImage(bytes);
        },
        renderGeometrySeam: (source, geom) {
          renderCount++;
          return img.copyResize(
            source,
            width: geom.destinationSize.width,
            height: geom.destinationSize.height,
          );
        },
        encodeJpgSeam: (image, {required quality}) {
          encodeCount++;
          return img.encodeJpg(image, quality: quality);
        },
      );

      final req = request(page);

      // Launch 3 simultaneous requests for the exact same page
      final results = await Future.wait([
        engine.process(req),
        engine.process(req),
        engine.process(req),
      ]);

      for (final r in results) {
        expect(r.isSuccess, isTrue);
      }

      // Exactly 1 heavy render pipeline executed; the other 2 reused cache post-queue
      expect(assets.rawReads, equals(1), reason: 'Only the winning request should read raw image');
      expect(decodeCount, equals(1), reason: 'Only 1 raw decode should occur');
      expect(renderCount, equals(1), reason: 'Only 1 perspective geometry render should occur');
      expect(encodeCount, equals(2), reason: 'Only 1 processed encode + 1 thumbnail encode');
      expect(assets.processedWrites, equals(1), reason: 'Only 1 processed image written');
      expect(assets.thumbnailWrites, equals(1), reason: 'Only 1 thumbnail written');
      expect(engine.maximumObservedHeavyJobs, equals(1));
      expect(engine.activeHeavyJobs, equals(0));
    });

    test('Test 3 — different-page concurrent isolation maintains bounded concurrency and distinct assets', () async {
      final assets = MemoryAssets();
      final page1 = ScanPage(
        id: 'page1',
        documentId: 'doc1',
        pageIndex: 0,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final page2 = ScanPage(
        id: 'page2',
        documentId: 'doc1',
        pageIndex: 1,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final page3 = ScanPage(
        id: 'page1',
        documentId: 'doc2',
        pageIndex: 0,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      assets.raw['doc1/page1'] = img.encodeJpg(img.Image(width: 8, height: 8));
      assets.raw['doc1/page2'] = img.encodeJpg(img.Image(width: 12, height: 12));
      assets.raw['doc2/page1'] = img.encodeJpg(img.Image(width: 16, height: 16));

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );

      final results = await Future.wait([
        engine.process(ProcessingRequest(
          documentId: 'doc1',
          pageId: 'page1',
          rawAssetIdentity: 'raw1',
          editState: PageEditStateSnapshot(page1),
          sourceSize: const PixelSize(1000, 1000),
        )),
        engine.process(ProcessingRequest(
          documentId: 'doc1',
          pageId: 'page2',
          rawAssetIdentity: 'raw2',
          editState: PageEditStateSnapshot(page2),
          sourceSize: const PixelSize(1000, 1000),
        )),
        engine.process(ProcessingRequest(
          documentId: 'doc2',
          pageId: 'page1',
          rawAssetIdentity: 'raw3',
          editState: PageEditStateSnapshot(page3),
          sourceSize: const PixelSize(1000, 1000),
        )),
      ]);

      for (final r in results) {
        expect(r.isSuccess, isTrue);
      }

      expect(assets.processed.containsKey('doc1/page1'), isTrue);
      expect(assets.processed.containsKey('doc1/page2'), isTrue);
      expect(assets.processed.containsKey('doc2/page1'), isTrue);
      expect(assets.thumbnails.containsKey('doc1/page1'), isTrue);
      expect(assets.thumbnails.containsKey('doc1/page2'), isTrue);
      expect(assets.thumbnails.containsKey('doc2/page1'), isTrue);
      expect(engine.maximumObservedHeavyJobs, equals(1));
      expect(engine.activeHeavyJobs, equals(0));
    });

    test('Test 4 — failure slot release: failed job releases lock so next job succeeds without deadlock', () async {
      final assets = MemoryAssets();
      assets.raw['doc/pageGood'] = img.encodeJpg(img.Image(width: 8, height: 8));

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
      );

      final badPage = ScanPage(
        id: 'pageBad',
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final goodPage = ScanPage(
        id: 'pageGood',
        documentId: 'doc',
        pageIndex: 1,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      // badPage has no raw asset in assets.raw, so readRawImage returns [] and process fails
      final results = await Future.wait([
        engine.process(ProcessingRequest(
          documentId: 'doc',
          pageId: 'pageBad',
          rawAssetIdentity: 'rawBad',
          editState: PageEditStateSnapshot(badPage),
          sourceSize: const PixelSize(1000, 1000),
        )),
        engine.process(ProcessingRequest(
          documentId: 'doc',
          pageId: 'pageGood',
          rawAssetIdentity: 'rawGood',
          editState: PageEditStateSnapshot(goodPage),
          sourceSize: const PixelSize(1000, 1000),
        )),
      ]);

      expect(results[0].isSuccess, isFalse);
      expect((results[0] as Failure).error, isA<ProcessingInputFailure>());
      expect(results[1].isSuccess, isTrue);
      expect(engine.maximumObservedHeavyJobs, equals(1));
      expect(engine.activeHeavyJobs, equals(0));
    });

    test('Test 5 — cancellation while queued: queued job exits cleanly without heavy raster work', () async {
      final assets = MemoryAssets();
      for (final id in ['pageA', 'pageB', 'pageC']) {
        assets.raw['doc/$id'] = img.encodeJpg(img.Image(width: 8, height: 8));
      }

      final aStarted = Completer<void>();
      final aRelease = Completer<void>();

      assets.onBeforeReadRaw = (doc, pageId) async {
        if (pageId == 'pageA') {
          if (!aStarted.isCompleted) aStarted.complete();
          await aRelease.future;
        }
      };

      final lock = AsyncProcessingLock();
      var cancelledB = false;

      final engineA = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        lock: lock,
      );
      final engineB = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        lock: lock,
        isCancelled: () => cancelledB,
      );
      final engineC = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        lock: lock,
      );

      ScanPage createPage(String id) => ScanPage(
        id: id,
        documentId: 'doc',
        pageIndex: 0,
        corners: corners,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      ProcessingRequest req(String id) => ProcessingRequest(
        documentId: 'doc',
        pageId: id,
        rawAssetIdentity: 'raw-$id',
        editState: PageEditStateSnapshot(createPage(id)),
        sourceSize: const PixelSize(1000, 1000),
      );

      // Start A — it pauses inside heavy work holding the lock
      final futureA = engineA.process(req('pageA'));
      await aStarted.future;

      // Enqueue B, then cancel it while it is queued
      final futureB = engineB.process(req('pageB'));
      cancelledB = true;

      // Enqueue C behind B
      final futureC = engineC.process(req('pageC'));

      // Release A
      aRelease.complete();

      final resA = await futureA;
      final resB = await futureB;
      final resC = await futureC;

      expect(resA.isSuccess, isTrue);
      expect(resB.isSuccess, isFalse);
      expect((resB as Failure).error, isA<ProcessingCancelledFailure>(),
          reason: 'B must be cancelled cleanly');
      expect(assets.processed.containsKey('doc/pageB'), isFalse,
          reason: 'Cancelled job B must not have produced any processed asset');
      expect(resC.isSuccess, isTrue,
          reason: 'C must succeed after B releases slot without deadlock');
      expect(lock.active, equals(0));
      expect(lock.queued, equals(0));
    });

    test('Test 6 — cache re-check post-queue acquisition skips raw read, decode, render, encode on B', () async {
      final assets = MemoryAssets();
      var decodeCount = 0;
      var renderCount = 0;
      var encodeCount = 0;

      final aStarted = Completer<void>();
      final aRelease = Completer<void>();

      assets.onBeforeReadRaw = (doc, pageId) async {
        if (!aStarted.isCompleted) {
          aStarted.complete();
          await aRelease.future;
        }
      };

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        decodeImageSeam: (bytes) {
          decodeCount++;
          return img.decodeImage(bytes);
        },
        renderGeometrySeam: (source, geom) {
          renderCount++;
          return img.copyResize(
            source,
            width: geom.destinationSize.width,
            height: geom.destinationSize.height,
          );
        },
        encodeJpgSeam: (image, {required quality}) {
          encodeCount++;
          return img.encodeJpg(image, quality: quality);
        },
      );

      final req = request(page);

      // Start A, pauses inside heavy lock
      final futureA = engine.process(req);
      await aStarted.future;

      // B queues behind A for the exact same page
      final futureB = engine.process(req);

      // Release A
      aRelease.complete();

      final resA = await futureA;
      final resB = await futureB;

      expect(resA.isSuccess, isTrue);
      expect(resB.isSuccess, isTrue);
      expect((resA as Success<ProcessingResult>).value.processedPath,
          equals((resB as Success<ProcessingResult>).value.processedPath));

      // B must have done 0 raw reads, 0 decodes, 0 renders, 0 encodes
      expect(assets.rawReads, equals(1), reason: 'Only A read raw image; B skipped');
      expect(decodeCount, equals(1), reason: 'Only A decoded; B skipped');
      expect(renderCount, equals(1), reason: 'Only A rendered; B skipped');
      expect(encodeCount, equals(2), reason: 'Only A encoded (1 processed + 1 thumbnail); B skipped');
      expect(engine.maximumObservedHeavyJobs, equals(1));
      expect(engine.activeHeavyJobs, equals(0));
    });

    test('Test 7 — forceReprocess concurrency serialization executes each sequentially with maxHeavyJobs <= 1', () async {
      final assets = MemoryAssets();
      var activeSimultaneous = 0;
      var maxSimultaneous = 0;

      final engine = M07ProcessingEngine(
        assets: assets,
        geometry: const PlainGeometryEngine(),
        onHeavyJobStarted: () {
          activeSimultaneous++;
          if (activeSimultaneous > maxSimultaneous) {
            maxSimultaneous = activeSimultaneous;
          }
        },
        onHeavyJobFinished: () {
          activeSimultaneous--;
        },
      );

      final forceReq = ProcessingRequest(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(page),
        sourceSize: const PixelSize(1000, 1000),
        forceReprocess: true,
      );

      final results = await Future.wait([
        engine.process(forceReq),
        engine.process(forceReq),
        engine.process(forceReq),
      ]);

      for (final r in results) {
        expect(r.isSuccess, isTrue);
      }

      expect(assets.processedWrites, equals(3), reason: 'All 3 forceReprocess requests must execute');
      expect(maxSimultaneous, equals(1), reason: 'Active simultaneous heavy jobs must never exceed 1');
      expect(activeSimultaneous, equals(0));
      expect(engine.maximumObservedHeavyJobs, equals(1));
      expect(engine.activeHeavyJobs, equals(0));
    });
  });
}

extension on ProcessingRequest {
  ProcessingRequest copyWithRaw(String raw) => ProcessingRequest(
    documentId: documentId,
    pageId: pageId,
    rawAssetIdentity: raw,
    editState: editState,
    sourceSize: sourceSize,
    forceReprocess: forceReprocess,
    thumbnail: thumbnail,
  );
}
