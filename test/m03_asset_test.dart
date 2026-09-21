import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanora/app/core/result/result.dart';
import 'package:scanora/app/data/datasources/scanora_database.dart';
import 'package:scanora/app/data/repositories/sqlite_document_repository_v2.dart';
import 'package:scanora/app/domain/contracts/asset_store.dart';
import 'package:scanora/app/domain/entities/scan_document.dart';
import 'package:scanora/app/domain/entities/scan_page.dart';
import 'package:scanora/app/infrastructure/storage/document_asset_path_resolver.dart';
import 'package:scanora/app/infrastructure/storage/file_system_asset_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory root;
  late FileSystemAssetStore store;
  late DocumentAssetPathResolver resolver;

  setUp(() {
    root = Directory.systemTemp.createTempSync('scanora-m03-');
    store = FileSystemAssetStore(root);
    resolver = store.paths;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  String value<T>(Result<T> result) {
    expect(result, isA<Success<T>>());
    return (result as Success<T>).value as String;
  }

  test('canonical paths are deterministic and reject unsafe identifiers', () {
    expect(
      resolver.documentDirectory('doc-1'),
      path.join(root.path, 'documents', 'doc-1'),
    );
    expect(
      resolver.pageDirectory('doc-1', 'page-1'),
      path.join(root.path, 'documents', 'doc-1', 'pages', 'page-1'),
    );
    expect(
      resolver.rawImagePath('doc-1', 'page-1'),
      endsWith(path.join('page-1', 'raw.jpg')),
    );
    expect(
      resolver.processedImagePath('doc-1', 'page-1'),
      endsWith(path.join('page-1', 'processed.jpg')),
    );
    expect(
      resolver.thumbnailPath('doc-1', 'page-1'),
      endsWith(path.join('page-1', 'thumbnail.jpg')),
    );
    expect(
      resolver.exportsDirectory('doc-1'),
      endsWith(path.join('doc-1', 'exports')),
    );

    for (final id in [
      '',
      ' ',
      '.',
      '..',
      '../x',
      r'foo\bar',
      'foo/bar',
      '/absolute',
    ]) {
      expect(() => resolver.documentDirectory(id), throwsA(isA<Exception>()));
    }
  });

  test('directory creation is idempotent', () async {
    final first = await store.createDocumentStorage('doc-1');
    final second = await store.createDocumentStorage('doc-1');
    final page = await store.createPageStorage('doc-1', 'page-1');

    expect(value(first), isNotEmpty);
    expect(value(second), value(first));
    expect(value(page), isNotEmpty);
    expect(Directory(resolver.pagesDirectory('doc-1')).existsSync(), isTrue);
    expect(Directory(resolver.exportsDirectory('doc-1')).existsSync(), isTrue);
  });

  test('raw, processed, and thumbnail assets are independent', () async {
    final raw = <int>[1, 2, 3];
    final processed = <int>[4, 5];
    final thumbnail = <int>[6];

    final rawPath = value(await store.saveRawImage('doc-1', 'page-1', raw));
    final processedPath = value(
      await store.saveProcessedImage('doc-1', 'page-1', processed),
    );
    final thumbnailPath = value(
      await store.saveThumbnail('doc-1', 'page-1', thumbnail),
    );

    expect(File(rawPath).readAsBytesSync(), raw);
    expect(File(processedPath).readAsBytesSync(), processed);
    expect(File(thumbnailPath).readAsBytesSync(), thumbnail);
    expect((await store.readRawImage('doc-1', 'page-1')).valueOrNull, raw);
    expect(
      (await store.readProcessedImage('doc-1', 'page-1')).valueOrNull,
      processed,
    );
    expect(
      (await store.readThumbnail('doc-1', 'page-1')).valueOrNull,
      thumbnail,
    );
    expect(
      Directory(root.path)
          .listSync(recursive: true)
          .where((entity) => entity.path.endsWith('.tmp'))
          .isEmpty,
      isTrue,
    );

    value(await store.saveProcessedImage('doc-1', 'page-1', [8, 9]));
    expect(File(rawPath).readAsBytesSync(), raw);
    expect(File(thumbnailPath).readAsBytesSync(), thumbnail);
    expect(File(processedPath).readAsBytesSync(), [8, 9]);
  });

  test('missing reads return typed failures', () async {
    final result = await store.readRawImage('doc-1', 'page-1');
    expect(result, isA<Failure<List<int>>>());
  });

  test('page and document deletion are isolated and idempotent', () async {
    value(await store.saveRawImage('doc-1', 'page-1', [1]));
    value(await store.saveProcessedImage('doc-1', 'page-1', [2]));
    value(await store.saveThumbnail('doc-1', 'page-1', [3]));
    value(await store.saveRawImage('doc-1', 'page-2', [4]));
    value(await store.saveRawImage('doc-2', 'page-1', [5]));

    expect((await store.deletePageAssets('doc-1', 'page-1')).isSuccess, isTrue);
    expect(
      Directory(resolver.pageDirectory('doc-1', 'page-1')).existsSync(),
      isFalse,
    );
    expect(File(resolver.rawImagePath('doc-1', 'page-2')).existsSync(), isTrue);
    expect(File(resolver.rawImagePath('doc-2', 'page-1')).existsSync(), isTrue);
    expect((await store.deletePageAssets('doc-1', 'page-1')).isSuccess, isTrue);

    await Directory(resolver.exportsDirectory('doc-1')).create(recursive: true);
    await File(
      path.join(resolver.exportsDirectory('doc-1'), 'export.pdf'),
    ).writeAsBytes([7]);
    expect((await store.deleteDocumentAssets('doc-1')).isSuccess, isTrue);
    expect(
      Directory(resolver.documentDirectory('doc-1')).existsSync(),
      isFalse,
    );
    expect(File(resolver.rawImagePath('doc-2', 'page-1')).existsSync(), isTrue);
    expect((await store.deleteDocumentAssets('doc-1')).isSuccess, isTrue);
  });

  test(
    'integrity scanner detects missing, orphan, and unknown assets without deletion',
    () async {
      value(await store.saveRawImage('doc-1', 'page-1', [1]));
      value(await store.saveProcessedImage('doc-1', 'page-1', [2]));
      await Directory(
        resolver.pageDirectory('doc-1', 'page-1'),
      ).create(recursive: true);
      await File(
        path.join(resolver.pageDirectory('doc-1', 'page-1'), 'unexpected.bin'),
      ).writeAsBytes([3]);
      await Directory(
        resolver.pageDirectory('doc-1', 'orphan-page'),
      ).create(recursive: true);
      await Directory(
        resolver.documentDirectory('orphan-document'),
      ).create(recursive: true);

      final report =
          (await store.inspectIntegrity(
            documentIds: const ['doc-1'],
            pages: const [(documentId: 'doc-1', pageId: 'page-1')],
            referencedAssets: const [
              (documentId: 'doc-1', pageId: 'page-1', kind: AssetKind.raw),
              (
                documentId: 'doc-1',
                pageId: 'page-1',
                kind: AssetKind.processed,
              ),
              (
                documentId: 'doc-1',
                pageId: 'page-1',
                kind: AssetKind.thumbnail,
              ),
            ],
          )).valueOrNull!;

      expect(report.missingThumbnails, contains('doc-1/page-1'));
      expect(report.orphanPages, contains('doc-1/orphan-page'));
      expect(report.orphanDocuments, contains('orphan-document'));
      expect(report.unknownFiles, contains(endsWith('unexpected.bin')));
      expect(
        File(resolver.rawImagePath('doc-1', 'page-1')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'canonical paths persist through the v2 repository and deletion cleans assets',
    () async {
      final databasePath = path.join(root.path, 'metadata.db');
      final database = ScanoraDatabase(databasePath: databasePath);
      final repository = SqliteDocumentRepositoryV2(
        database: database,
        assetStore: store,
      );
      addTearDown(database.close);
      final now = DateTime.utc(2026);
      final rawPath = value(await store.saveRawImage('doc-1', 'page-1', [1]));
      final processedPath = value(
        await store.saveProcessedImage('doc-1', 'page-1', [2]),
      );
      final thumbnailPath = value(
        await store.saveThumbnail('doc-1', 'page-1', [3]),
      );
      await repository.save(
        ScanDocument(
          id: 'doc-1',
          title: 'Canonical',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'page-1',
              documentId: 'doc-1',
              pageIndex: 0,
              rawImagePath: rawPath,
              processedImagePath: processedPath,
              thumbnailPath: thumbnailPath,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final restored = (await repository.getById('doc-1'))!;
      expect(restored.pages.single.rawImagePath, rawPath);
      expect(restored.pages.single.processedImagePath, processedPath);
      expect(restored.pages.single.thumbnailPath, thumbnailPath);
      await repository.delete('doc-1');
      expect(
        Directory(resolver.documentDirectory('doc-1')).existsSync(),
        isFalse,
      );
    },
  );

  test('saving after removing a page cleans its canonical assets', () async {
    final databasePath = path.join(root.path, 'page-removal.db');
    final database = ScanoraDatabase(databasePath: databasePath);
    final repository = SqliteDocumentRepositoryV2(
      database: database,
      assetStore: store,
    );
    addTearDown(database.close);
    final now = DateTime.utc(2026);
    final removedPath = value(await store.saveRawImage('doc-1', 'page-1', [1]));
    final retainedPath = value(
      await store.saveRawImage('doc-1', 'page-2', [2]),
    );
    final removed = ScanPage(
      id: 'page-1',
      documentId: 'doc-1',
      pageIndex: 0,
      rawImagePath: removedPath,
      createdAt: now,
      updatedAt: now,
    );
    final retained = ScanPage(
      id: 'page-2',
      documentId: 'doc-1',
      pageIndex: 1,
      rawImagePath: retainedPath,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(
      ScanDocument(
        id: 'doc-1',
        title: 'Pages',
        createdAt: now,
        updatedAt: now,
        pages: [removed, retained],
      ),
    );
    await repository.save(
      ScanDocument(
        id: 'doc-1',
        title: 'Pages',
        createdAt: now,
        updatedAt: now,
        pages: [retained],
      ),
    );
    expect(File(removedPath).existsSync(), isFalse);
    expect(File(retainedPath).existsSync(), isTrue);
  });
}
