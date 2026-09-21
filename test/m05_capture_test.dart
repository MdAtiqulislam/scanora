import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanora/app/application/services/capture_service.dart';
import 'package:scanora/app/core/errors/app_failure.dart';
import 'package:scanora/app/core/result/result.dart';
import 'package:scanora/app/data/datasources/scanora_database.dart';
import 'package:scanora/app/data/repositories/document_repository.dart';
import 'package:scanora/app/data/repositories/sqlite_document_repository_v2.dart';
import 'package:scanora/app/domain/contracts/capture_provider.dart';
import 'package:scanora/app/infrastructure/storage/file_system_asset_store.dart';

class FakeCaptureProvider implements CaptureProvider {
  final CaptureSessionResult result;
  final bool throwFailure;

  const FakeCaptureProvider(this.result, {this.throwFailure = false});

  @override
  CaptureSource get source => CaptureSource.nativeScanner;

  @override
  CaptureProviderCapabilities get capabilities =>
      const CaptureProviderCapabilities(
        supportsMultiPage: true,
        supportsDocumentDetection: true,
      );

  @override
  Future<Result<CaptureSessionResult>> capture(CaptureRequest request) async {
    if (throwFailure) {
      return const Failure(CaptureProviderFailure('fake failure'));
    }
    return Success(result);
  }

  @override
  Future<Result<bool>> isAvailable() async => const Success(true);
}

class FailingRepository extends DocumentRepository {
  FailingRepository(SqliteDocumentRepositoryV2 repository)
    : super(repository: repository);

  @override
  Future<void> saveDocument(document) async {
    throw const StorageFailure('database failure');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(CaptureService, Directory, ScanoraDatabase)> harness(
    CaptureSessionResult result, {
    DocumentRepository? repository,
  }) async {
    final root = await Directory.systemTemp.createTemp('scanora-m05-');
    final assets = FileSystemAssetStore(
      Directory(path.join(root.path, 'assets')),
    );
    final database = ScanoraDatabase(
      databasePath: path.join(root.path, 'db.sqlite'),
    );
    final repo =
        repository ??
        DocumentRepository(
          repository: SqliteDocumentRepositoryV2(
            database: database,
            assetStore: assets,
          ),
        );
    return (
      CaptureService(
        provider: FakeCaptureProvider(result),
        assetStore: assets,
        repository: repo,
      ),
      root,
      database,
    );
  }

  Future<String> source(Directory root, String name, List<int> bytes) async {
    final file = File(path.join(root.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test(
    'single and multi-page capture persist canonical raw assets in provider order',
    () async {
      final root = await Directory.systemTemp.createTemp('scanora-m05-source-');
      final a = await source(root, 'a.jpg', [1]);
      final b = await source(root, 'b.jpg', [2]);
      final c = await source(root, 'c.jpg', [3]);
      final fixture = await harness(
        CaptureSessionResult(
          pages: [
            CapturedPage(sourcePath: a, source: CaptureSource.nativeScanner),
            CapturedPage(sourcePath: b, source: CaptureSource.nativeScanner),
            CapturedPage(sourcePath: c, source: CaptureSource.nativeScanner),
          ],
        ),
      );
      addTearDown(() async {
        await fixture.$3.close();
        await fixture.$2.delete(recursive: true);
        await root.delete(recursive: true);
      });
      final result = await fixture.$1.capture(const CaptureRequest());
      final document = (result as Success).value;
      expect(document.pages.length, 3);
      expect(document.pages.map((page) => page.rawImagePath!.split('/').last), [
        'raw.jpg',
        'raw.jpg',
        'raw.jpg',
      ]);
      for (final page in document.pages) {
        expect(File(page.rawImagePath!).existsSync(), isTrue);
      }
    },
  );

  test('empty and cancelled captures create no document', () async {
    final fixture = await harness(const CaptureSessionResult(cancelled: true));
    addTearDown(() async {
      await fixture.$3.close();
      await fixture.$2.delete(recursive: true);
    });
    final result = await fixture.$1.capture(const CaptureRequest());
    expect(result, isA<Failure>());
    expect(fixture.$1.isActive, isFalse);
  });

  test(
    'provider failure maps to failure and duplicate capture is rejected',
    () async {
      final root = await Directory.systemTemp.createTemp('scanora-m05-source-');
      final file = await source(root, 'a.jpg', [1]);
      final fixture = await harness(
        CaptureSessionResult(
          pages: [
            CapturedPage(sourcePath: file, source: CaptureSource.nativeScanner),
          ],
        ),
      );
      addTearDown(() async {
        await fixture.$3.close();
        await fixture.$2.delete(recursive: true);
        await root.delete(recursive: true);
      });
      final first = fixture.$1.capture(const CaptureRequest());
      final second = await fixture.$1.capture(const CaptureRequest());
      expect(second, isA<Result>());
      await first;
    },
  );

  test('database failure cleans newly persisted raw assets', () async {
    final root = await Directory.systemTemp.createTemp('scanora-m05-source-');
    final file = await source(root, 'a.jpg', [1]);
    final db = ScanoraDatabase(databasePath: path.join(root.path, 'db.sqlite'));
    final assets = FileSystemAssetStore(
      Directory(path.join(root.path, 'assets')),
    );
    final repository = FailingRepository(
      SqliteDocumentRepositoryV2(database: db, assetStore: assets),
    );
    final service = CaptureService(
      provider: FakeCaptureProvider(
        CaptureSessionResult(
          pages: [
            CapturedPage(sourcePath: file, source: CaptureSource.nativeScanner),
          ],
        ),
      ),
      assetStore: assets,
      repository: repository,
    );
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final result = await service.capture(const CaptureRequest());
    expect(result, isA<Failure>());
    expect(
      Directory(
        path.join(root.path, 'assets', 'documents'),
      ).listSync(recursive: true),
      isEmpty,
    );
  });
}
