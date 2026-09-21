import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/errors/processing_failure.dart';
import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/contracts/asset_store.dart';
import '../../domain/contracts/geometry_engine.dart';
import '../../domain/contracts/processing_engine.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/processing/processing_models.dart';
import '../../domain/enums/scan_enums.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/page_edit_state.dart';

class AsyncProcessingLock {
  final int maxConcurrency;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  AsyncProcessingLock({this.maxConcurrency = 1}) {
    assert(maxConcurrency >= 1, 'maxConcurrency must be at least 1');
  }

  int get active => _active;
  int get queued => _waiters.length;

  Future<void> acquire() {
    if (_active < maxConcurrency) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _active--;
      assert(_active >= 0, 'AsyncProcessingLock release called more times than acquired');
    }
  }
}

class M07ProcessingEngine implements ProcessingEngine {
  static const engineVersion = 'M07-v1';

  final AssetStore assets;
  final GeometryEngine geometry;
  final bool Function()? isCancelled;
  final MarkCacheCurrentCallback? markCacheCurrent;
  final img.Image? Function(Uint8List bytes)? decodeImageSeam;
  final img.Image Function(img.Image source, GeometryResult geometry)?
  renderGeometrySeam;
  final Uint8List Function(img.Image image, {required int quality})?
  encodeJpgSeam;

  final AsyncProcessingLock _lock;
  final void Function()? onHeavyJobStarted;
  final void Function()? onHeavyJobFinished;

  final Map<String, ({String processedKey, String thumbnailKey})> _committedCache = {};
  final Map<String, int> _activeForceReprocessPages = {};

  int _activeHeavyJobs = 0;
  int _maximumObservedHeavyJobs = 0;

  int get activeHeavyJobs => _activeHeavyJobs;
  int get maximumObservedHeavyJobs => _maximumObservedHeavyJobs;

  void resetInstrumentation() {
    _activeHeavyJobs = 0;
    _maximumObservedHeavyJobs = 0;
  }

  M07ProcessingEngine({
    required this.assets,
    required this.geometry,
    this.isCancelled,
    this.markCacheCurrent,
    this.decodeImageSeam,
    this.renderGeometrySeam,
    this.encodeJpgSeam,
    AsyncProcessingLock? lock,
    this.onHeavyJobStarted,
    this.onHeavyJobFinished,
  }) : _lock = lock ?? AsyncProcessingLock(maxConcurrency: 1);

  bool _isCancelled(ProcessingRequest request) =>
      request.isCancelled?.call() == true || isCancelled?.call() == true;

  @override
  Future<Result<ProcessingResult>> process(ProcessingRequest request) async {
    try {
      if (!request.thumbnail.isValid) {
        throw const ProcessingInputFailure('Invalid thumbnail specification');
      }

      if (request.forceReprocess) {
        _committedCache.remove(request.pageId);
        _activeForceReprocessPages.update(
          request.pageId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      if (_isCancelled(request)) throw const ProcessingCancelledFailure();

      final page = request.editState.page;
      final corners = page.corners;
      if (corners == null) {
        throw const ProcessingInputFailure('Page geometry is unavailable');
      }
      final geometryResult = geometry.calculate(
        corners: corners,
        sourceSize: request.sourceSize,
        rotationDegrees: 0,
      );
      if (geometryResult case Failure<GeometryResult>(:final error)) {
        throw ProcessingStageFailure('Geometry failed', cause: error);
      }
      final geometryValue = (geometryResult as Success).value;
      if (page.filterType != ScanFilterType.original) {
        throw UnsupportedProcessingProfileFailure(
          'M07 does not implement ${page.filterType.name} rendering',
        );
      }

      final processedKey = PageCacheIdentity.forProcessed(
        engineVersion: engineVersion,
        documentId: request.documentId,
        pageId: request.pageId,
        rawAssetIdentity: request.rawAssetIdentity,
        editState: page.editState,
        geometryTransform: geometryValue.transform.coefficients,
      );
      final thumbnailKey = PageCacheIdentity.forThumbnail(
        processedCacheKey: processedKey,
        width: request.thumbnail.width,
        height: request.thumbnail.height,
        quality: request.thumbnail.quality,
      );
      final plan = ProcessingPlan(
        engineVersion: engineVersion,
        processedCacheKey: processedKey,
        thumbnailCacheKey: thumbnailKey,
        geometry: geometryValue,
        supportsProfile: page.filterType == ScanFilterType.original,
      );

      // Lightweight Pre-Queue Cache Check (zero I/O, no lock contention)
      final processedExistsRes = await assets.exists(
        request.documentId,
        request.pageId,
        AssetKind.processed,
      );
      if (processedExistsRes case Failure<bool>(:final error)) return Failure(error);
      final processedExists = (processedExistsRes as Success<bool>).value;

      final thumbnailExistsRes = await assets.exists(
        request.documentId,
        request.pageId,
        AssetKind.thumbnail,
      );
      if (thumbnailExistsRes case Failure<bool>(:final error)) return Failure(error);
      final thumbnailExists = (thumbnailExistsRes as Success<bool>).value;

      if (!processedExists || !thumbnailExists) {
        _committedCache.remove(request.pageId);
      }

      final processedMatch =
          processedExists && page.processedCacheKey == processedKey;
      final thumbnailMatch =
          thumbnailExists && page.thumbnailCacheKey == thumbnailKey;

      final isActivelyReprocessing =
          (_activeForceReprocessPages[request.pageId] ?? 0) > 0;

      if (!request.forceReprocess &&
          !isActivelyReprocessing &&
          processedMatch &&
          thumbnailMatch) {
        final processedPathRes = await assets.pathFor(
          request.documentId,
          request.pageId,
          AssetKind.processed,
        );
        if (processedPathRes case Failure<String>(:final error)) return Failure(error);
        final thumbnailPathRes = await assets.pathFor(
          request.documentId,
          request.pageId,
          AssetKind.thumbnail,
        );
        if (thumbnailPathRes case Failure<String>(:final error)) return Failure(error);

        return Success(
          ProcessingResult(
            processedPath: (processedPathRes as Success<String>).value,
            thumbnailPath: (thumbnailPathRes as Success<String>).value,
            plan: plan,
          ),
        );
      }

      // Acquire serialized heavy processing lock
      await _lock.acquire();
      try {
        if (_isCancelled(request)) {
          throw const ProcessingCancelledFailure();
        }

        final encodeFn = encodeJpgSeam ?? img.encodeJpg;
        final decodeFn = decodeImageSeam ?? img.decodeImage;

        // Post-Queue Cache Re-check: If an earlier concurrent request for this page
        // completed while this request was waiting, reuse the committed cache.
        if (!request.forceReprocess) {
          final committed = _committedCache[request.pageId];
          final recheckProcessedExistsRes = await assets.exists(
            request.documentId,
            request.pageId,
            AssetKind.processed,
          );
          if (recheckProcessedExistsRes case Failure<bool>(:final error)) throw error;
          final recheckProcessedExists = (recheckProcessedExistsRes as Success<bool>).value;

          final recheckThumbnailExistsRes = await assets.exists(
            request.documentId,
            request.pageId,
            AssetKind.thumbnail,
          );
          if (recheckThumbnailExistsRes case Failure<bool>(:final error)) throw error;
          final recheckThumbnailExists = (recheckThumbnailExistsRes as Success<bool>).value;

          if (!recheckProcessedExists || !recheckThumbnailExists) {
            _committedCache.remove(request.pageId);
          }

          final recheckProcessedMatch =
              recheckProcessedExists &&
              (page.processedCacheKey == processedKey ||
                  committed?.processedKey == processedKey);
          final recheckThumbnailMatch =
              recheckThumbnailExists &&
              (page.thumbnailCacheKey == thumbnailKey ||
                  committed?.thumbnailKey == thumbnailKey);

          if (recheckProcessedMatch && recheckThumbnailMatch) {
            final processedPathRes = await assets.pathFor(
              request.documentId,
              request.pageId,
              AssetKind.processed,
            );
            if (processedPathRes case Failure<String>(:final error)) throw error;
            final thumbnailPathRes = await assets.pathFor(
              request.documentId,
              request.pageId,
              AssetKind.thumbnail,
            );
            if (thumbnailPathRes case Failure<String>(:final error)) throw error;

            return Success(
              ProcessingResult(
                processedPath: (processedPathRes as Success<String>).value,
                thumbnailPath: (thumbnailPathRes as Success<String>).value,
                plan: plan,
              ),
            );
          }

          // Partial Cache Hit: Processed asset is current, only thumbnail needs generation
          if (recheckProcessedMatch && !recheckThumbnailMatch) {
            if (_isCancelled(request)) {
              throw const ProcessingCancelledFailure();
            }
            _activeHeavyJobs++;
            if (_activeHeavyJobs > _maximumObservedHeavyJobs) {
              _maximumObservedHeavyJobs = _activeHeavyJobs;
            }
            onHeavyJobStarted?.call();
            try {
              final processedRaw = await assets.readProcessedImage(
                request.documentId,
                request.pageId,
              );
              if (processedRaw case Failure<List<int>>(:final error)) {
                throw ProcessingInputFailure(
                  'Processed asset unavailable',
                  cause: error,
                );
              }
              final processedRawBytes = (processedRaw as Success<List<int>>).value;
              final processedUint8 =
                  processedRawBytes is Uint8List
                      ? processedRawBytes
                      : Uint8List.fromList(processedRawBytes);
              final processedImage = decodeFn(processedUint8);
              if (processedImage == null) {
                throw const ProcessingInputFailure(
                  'Processed asset could not be decoded',
                );
              }
              if (_isCancelled(request)) {
                throw const ProcessingCancelledFailure();
              }
              final thumbnailImage = _thumbnail(
                processedImage,
                request.thumbnail.width,
                request.thumbnail.height,
              );
              final thumbnailBytes = encodeFn(
                thumbnailImage,
                quality: request.thumbnail.quality,
              );
              final thumbnail = await assets.saveThumbnail(
                request.documentId,
                request.pageId,
                thumbnailBytes,
              );
              if (thumbnail case Failure<String>(:final error)) {
                throw ProcessingPersistenceFailure(
                  'Thumbnail persistence failed',
                  cause: error,
                );
              }
              if (markCacheCurrent != null) {
                try {
                  await _invokeMarkCacheCurrent(
                    pageId: request.pageId,
                    processedKey: processedKey,
                    thumbnailKey: thumbnailKey,
                    expectedRawAssetIdentity: request.rawAssetIdentity,
                    expectedEditState: page.editState,
                  );
                } catch (error, stackTrace) {
                  throw ProcessingPersistenceFailure(
                    'Cache persistence failed',
                    cause: error,
                    stackTrace: stackTrace,
                  );
                }
              }
              _committedCache[request.pageId] = (
                processedKey: processedKey,
                thumbnailKey: thumbnailKey,
              );
              final processedPathResult = await assets.pathFor(
                    request.documentId,
                    request.pageId,
                    AssetKind.processed,
                  );
              if (processedPathResult case Failure<String>(:final error)) {
                throw ProcessingPersistenceFailure(
                  'Failed to resolve processed asset path',
                  cause: error,
                );
              }
              final processedPath = (processedPathResult as Success<String>).value;
              return Success(
                ProcessingResult(
                  processedPath: processedPath,
                  thumbnailPath: (thumbnail as Success<String>).value,
                  plan: plan,
                ),
              );
            } finally {
              _activeHeavyJobs--;
              onHeavyJobFinished?.call();
            }
          }
        }

        // Full heavy raster pipeline
        if (_isCancelled(request)) {
          throw const ProcessingCancelledFailure();
        }
        _activeHeavyJobs++;
        if (_activeHeavyJobs > _maximumObservedHeavyJobs) {
          _maximumObservedHeavyJobs = _activeHeavyJobs;
        }
        onHeavyJobStarted?.call();
        try {
          final raw = await assets.readRawImage(
            request.documentId,
            request.pageId,
          );
          if (raw case Failure<List<int>>(:final error)) {
            throw ProcessingInputFailure('Raw asset unavailable', cause: error);
          }
          final rawBytes = (raw as Success<List<int>>).value;
          if (rawBytes.isEmpty) {
            throw const ProcessingInputFailure('Raw asset is empty');
          }
          if (_isCancelled(request)) {
            throw const ProcessingCancelledFailure();
          }

          final rawUint8 =
              rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);
          final decoded = decodeFn(rawUint8);
          if (decoded == null) {
            throw const ProcessingInputFailure('Raw asset could not be decoded');
          }
          if (_isCancelled(request)) {
            throw const ProcessingCancelledFailure();
          }

          final renderFn = renderGeometrySeam ?? _renderGeometry;
          final rendered = renderFn(decoded, geometryValue);
          if (_isCancelled(request)) {
            throw const ProcessingCancelledFailure();
          }

          final rotated = _applyRotation(rendered, page.rotationAngle.round());
          final processedBytes = encodeFn(rotated, quality: 92);
          final processed = await assets.saveProcessedImage(
            request.documentId,
            request.pageId,
            processedBytes,
          );
          if (processed case Failure<String>(:final error)) {
            throw ProcessingPersistenceFailure(
              'Processed asset persistence failed',
              cause: error,
            );
          }
          if (_isCancelled(request)) {
            throw const ProcessingCancelledFailure();
          }

          final thumbnailImage = _thumbnail(
            rotated,
            request.thumbnail.width,
            request.thumbnail.height,
          );
          final thumbnailBytes = encodeFn(
            thumbnailImage,
            quality: request.thumbnail.quality,
          );
          final thumbnail = await assets.saveThumbnail(
            request.documentId,
            request.pageId,
            thumbnailBytes,
          );
          if (thumbnail case Failure<String>(:final error)) {
            throw ProcessingPersistenceFailure(
              'Thumbnail persistence failed',
              cause: error,
            );
          }
          if (markCacheCurrent != null) {
            try {
              await _invokeMarkCacheCurrent(
                pageId: request.pageId,
                processedKey: processedKey,
                thumbnailKey: thumbnailKey,
                expectedRawAssetIdentity: request.rawAssetIdentity,
                expectedEditState: page.editState,
              );
            } catch (error, stackTrace) {
              throw ProcessingPersistenceFailure(
                'Cache persistence failed',
                cause: error,
                stackTrace: stackTrace,
              );
            }
          }
          _committedCache[request.pageId] = (
            processedKey: processedKey,
            thumbnailKey: thumbnailKey,
          );
          return Success(
            ProcessingResult(
              processedPath: (processed as Success<String>).value,
              thumbnailPath: (thumbnail as Success<String>).value,
              plan: plan,
            ),
          );
        } finally {
          _activeHeavyJobs--;
          onHeavyJobFinished?.call();
        }
      } finally {
        _lock.release();
      }
    } catch (error, stackTrace) {
      if (error is ProcessingFailure) return Failure(error);
      return Failure(
        ProcessingStageFailure(
          'Processing failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      if (request.forceReprocess) {
        final count = _activeForceReprocessPages[request.pageId] ?? 0;
        if (count <= 1) {
          _activeForceReprocessPages.remove(request.pageId);
        } else {
          _activeForceReprocessPages[request.pageId] = count - 1;
        }
      }
    }
  }

  img.Image renderGeometry(img.Image source, GeometryResult geometry) =>
      _renderGeometry(source, geometry);

  img.Image applyRotation(img.Image image, int degrees) =>
      _applyRotation(image, degrees);

  static bool _isIdentityTransform(
    List<double> c,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (srcW != dstW || srcH != dstH) return false;
    const eps = 1e-6;
    return (c[0] - 1.0).abs() < eps &&
        c[1].abs() < eps &&
        c[2].abs() < eps &&
        c[3].abs() < eps &&
        (c[4] - 1.0).abs() < eps &&
        c[5].abs() < eps &&
        c[6].abs() < eps &&
        c[7].abs() < eps &&
        (c[8] - 1.0).abs() < eps;
  }

  img.Image _renderGeometry(img.Image source, GeometryResult geometry) {
    final width = geometry.destinationSize.width;
    final height = geometry.destinationSize.height;
    if (_isIdentityTransform(
      geometry.transform.coefficients,
      source.width,
      source.height,
      width,
      height,
    )) {
      return img.Image.from(source);
    }
    final output = img.Image(width: width, height: height);
    final inverse = _inverse(geometry.transform.coefficients);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final denominator = inverse[6] * x + inverse[7] * y + inverse[8];
        if (denominator.abs() < 1e-12) continue;
        final sx = (inverse[0] * x + inverse[1] * y + inverse[2]) / denominator;
        final sy = (inverse[3] * x + inverse[4] * y + inverse[5]) / denominator;
        final ix = sx.round();
        final iy = sy.round();
        if (ix >= 0 && ix < source.width && iy >= 0 && iy < source.height) {
          output.setPixel(x, y, source.getPixel(ix, iy));
        }
      }
    }
    return output;
  }

  img.Image _thumbnail(img.Image source, int maxWidth, int maxHeight) {
    if (source.width <= maxWidth && source.height <= maxHeight) return source;
    final scale = math.min(maxWidth / source.width, maxHeight / source.height);
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  List<double> _inverse(List<double> matrix) {
    final a = matrix;
    final det =
        a[0] * (a[4] * a[8] - a[5] * a[7]) -
        a[1] * (a[3] * a[8] - a[5] * a[6]) +
        a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (det.abs() < 1e-12) {
      throw const ProcessingStageFailure('Geometry transform is singular');
    }
    return [
      (a[4] * a[8] - a[5] * a[7]) / det,
      (a[2] * a[7] - a[1] * a[8]) / det,
      (a[1] * a[5] - a[2] * a[4]) / det,
      (a[5] * a[6] - a[3] * a[8]) / det,
      (a[0] * a[8] - a[2] * a[6]) / det,
      (a[2] * a[3] - a[0] * a[5]) / det,
      (a[3] * a[7] - a[4] * a[6]) / det,
      (a[1] * a[6] - a[0] * a[7]) / det,
      (a[0] * a[4] - a[1] * a[3]) / det,
    ];
  }

  img.Image _applyRotation(img.Image image, int degrees) {
    final turns = ((degrees % 360) + 360) % 360;
    if (turns == 0) return image;
    return img.copyRotate(image, angle: turns);
  }

  Future<void> _invokeMarkCacheCurrent({
    required String pageId,
    required String processedKey,
    required String thumbnailKey,
    required String expectedRawAssetIdentity,
    required PageEditState expectedEditState,
  }) async {
    final fn = markCacheCurrent;
    if (fn == null) return;
    final result = await fn(
      pageId: pageId,
      processedCacheKey: processedKey,
      thumbnailCacheKey: thumbnailKey,
      expectedRawAssetIdentity: expectedRawAssetIdentity,
      expectedEditState: expectedEditState,
    );
    if (result case Failure<void>(:final error)) {
      throw error;
    }
  }

  @override
  Future<Result<List<int>>> renderPreview({
    required List<int> sourceBytes,
    required PageCorners corners,
    int quarterTurns = 0,
  }) async {
    try {
      final decodeFn = decodeImageSeam ?? img.decodeImage;
      final encodeFn = encodeJpgSeam ?? img.encodeJpg;

      final sourceUint8 =
          sourceBytes is Uint8List
              ? sourceBytes
              : Uint8List.fromList(sourceBytes);
      final decoded = decodeFn(sourceUint8);
      if (decoded == null) {
        return const Failure(
          ProcessingInputFailure('Source bytes could not be decoded'),
        );
      }

      final geometryResult = geometry.calculate(
        corners: corners,
        sourceSize: PixelSize(
          decoded.width,
          decoded.height,
        ),
        rotationDegrees: 0,
      );
      if (geometryResult case Failure<GeometryResult>(:final error)) {
        return Failure(
          ProcessingStageFailure(
            'Preview geometry calculation failed',
            cause: error,
          ),
        );
      }
      final geometryValue = (geometryResult as Success<GeometryResult>).value;

      final renderFn = renderGeometrySeam ?? _renderGeometry;
      final rendered = renderFn(decoded, geometryValue);
      final rotated = _applyRotation(rendered, quarterTurns * 90);
      final outputBytes = encodeFn(rotated, quality: 85);
      return Success(outputBytes);
    } catch (e, st) {
      return Failure(
        ProcessingStageFailure(
          'Preview render failed',
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }
}
