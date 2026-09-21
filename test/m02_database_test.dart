import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanora/app/data/datasources/scanora_database.dart';
import 'package:scanora/app/data/repositories/sqlite_document_repository_v2.dart';
import 'package:scanora/app/domain/enums/scan_enums.dart';

void main() {
  const timestamp = '2026-01-01T00:00:00.000Z';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<String> temporaryPath(String name) async {
    final directory = await Directory.systemTemp.createTemp('scanora-m02-');
    return path.join(directory.path, '$name.db');
  }

  Future<void> cleanup(String databasePath) async {
    final directory = Directory(path.dirname(databasePath));
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  Future<void> createLegacyDatabase(
    String databasePath,
    List<Map<String, Object?>> rows,
  ) async {
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE documents (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              pages TEXT NOT NULL,
              pdfPath TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    for (final row in rows) {
      await db.insert('documents', row);
    }
    await db.close();
  }

  Map<String, Object?> legacyDocument(
    String id,
    List<Map<String, Object?>> pages, {
    String title = 'Legacy document',
    Object? pdfPath = '/legacy.pdf',
    String createdAt = timestamp,
    String updatedAt = timestamp,
  }) => {
    'id': id,
    'title': title,
    'pages': jsonEncode(pages),
    'pdfPath': pdfPath,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  Map<String, Object?> legacyPage(
    String id,
    int index, {
    String filter = 'smart',
    String? rawPath,
  }) => {
    'id': id,
    'imagePath': '/processed/$index.jpg',
    'rawImagePath': rawPath ?? '/raw/$index.jpg',
    'filter': filter,
    'createdAt': timestamp,
  };

  test('real onUpgrade migrates one document and one page', () async {
    final databasePath = await temporaryPath('single');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-1', [legacyPage('page-1', 0, filter: 'magic')]),
    ]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final repository = SqliteDocumentRepositoryV2(database: database);
    final document = await repository.getById('doc-1');
    final db = await database.open();
    final documentRow = (await db.query('documents')).single;
    final pageRow = (await db.query('pages')).single;

    expect(document!.id, 'doc-1');
    expect(document.title, 'Legacy document');
    expect(document.createdAt, DateTime.parse(timestamp));
    expect(document.pdfPath, '/legacy.pdf');
    expect(document.pageCount, 1);
    expect(document.pages.single.id, 'page-1');
    expect(document.pages.single.pageIndex, 0);
    expect(document.pages.single.rawImagePath, '/raw/0.jpg');
    expect(document.pages.single.processedImagePath, '/processed/0.jpg');
    expect(document.pages.single.filterType, ScanFilterType.magic);
    expect(documentRow['id'], 'doc-1');
    expect(documentRow['title'], 'Legacy document');
    expect(documentRow['created_at'], timestamp);
    expect(documentRow['updated_at'], timestamp);
    expect(documentRow['favorite'], 0);
    expect(documentRow['tags_json'], '[]');
    expect(documentRow['pdf_path'], '/legacy.pdf');
    expect(documentRow['page_count'], 1);
    expect(pageRow['id'], 'page-1');
    expect(pageRow['document_id'], 'doc-1');
    expect(pageRow['page_index'], 0);
    expect(pageRow['raw_image_path'], '/raw/0.jpg');
    expect(pageRow['processed_image_path'], '/processed/0.jpg');
    expect(pageRow['thumbnail_path'], isNull);
    expect(pageRow['corners_json'], isNull);
    expect(pageRow['rotation_angle'], 0);
    expect(pageRow['crop_transform_json'], '{}');
    expect(pageRow['ocr_result'], isNull);
    expect(pageRow['is_dirty'], 0);
    expect(pageRow['created_at'], timestamp);
    expect(pageRow['updated_at'], timestamp);
  });

  test('real migration preserves five-page ordering and paths', () async {
    final databasePath = await temporaryPath('multi');
    addTearDown(() => cleanup(databasePath));
    final pages = List.generate(5, (index) => legacyPage('page-$index', index));
    await createLegacyDatabase(databasePath, [legacyDocument('doc-5', pages)]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final repository = SqliteDocumentRepositoryV2(database: database);
    final document = await repository.getById('doc-5');

    expect(document!.pages.map((page) => page.id), [
      'page-0',
      'page-1',
      'page-2',
      'page-3',
      'page-4',
    ]);
    expect(document.pages.map((page) => page.pageIndex), [0, 1, 2, 3, 4]);
    expect(document.pages.map((page) => page.processedImagePath), [
      '/processed/0.jpg',
      '/processed/1.jpg',
      '/processed/2.jpg',
      '/processed/3.jpg',
      '/processed/4.jpg',
    ]);
    expect(document.pageCount, 5);
  });

  test('real migration isolates multiple documents and page counts', () async {
    final databasePath = await temporaryPath('multiple');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-a', [legacyPage('a-0', 0)]),
      legacyDocument('doc-b', List.generate(3, (i) => legacyPage('b-$i', i))),
      legacyDocument('doc-c', List.generate(5, (i) => legacyPage('c-$i', i))),
    ]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final repository = SqliteDocumentRepositoryV2(database: database);
    final documents = await repository.getAll();

    expect(documents.map((document) => document.id), [
      'doc-a',
      'doc-b',
      'doc-c',
    ]);
    expect((await repository.getById('doc-a'))!.pageCount, 1);
    expect((await repository.getById('doc-b'))!.pages.map((page) => page.id), [
      'b-0',
      'b-1',
      'b-2',
    ]);
    expect((await repository.getById('doc-c'))!.pageCount, 5);
    for (final document in documents) {
      final db = await database.open();
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM pages WHERE document_id = ?',
        [document.id],
      );
      expect(result.single['count'], document.pageCount);
    }
  });

  test('empty page IDs receive stable collision-safe fallback IDs', () async {
    final databasePath = await temporaryPath('collision');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-1', [
        legacyPage('', 0),
        legacyPage('doc-1-page-0', 1),
        legacyPage('', 2),
      ]),
    ]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final repository = SqliteDocumentRepositoryV2(database: database);
    final first =
        (await repository.getById(
          'doc-1',
        ))!.pages.map((page) => page.id).toList();
    await database.close();
    final reopened = ScanoraDatabase(databasePath: databasePath);
    addTearDown(reopened.close);
    final second =
        (await SqliteDocumentRepositoryV2(
          database: reopened,
        ).getById('doc-1'))!.pages.map((page) => page.id).toList();

    expect(first, ['doc-1-page-0-migrated-1', 'doc-1-page-0', 'doc-1-page-2']);
    expect(second, first);
    expect(first.toSet().length, 3);
  });

  test('optional legacy values receive documented defaults', () async {
    final databasePath = await temporaryPath('defaults');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-defaults', [
        legacyPage('page-1', 0, rawPath: ''),
      ], pdfPath: null),
    ]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final repository = SqliteDocumentRepositoryV2(database: database);
    final document = await repository.getById('doc-defaults');
    final db = await database.open();
    final pageRow = (await db.query('pages')).single;
    final documentRow = (await db.query('documents')).single;

    expect(document!.pdfPath, isNull);
    expect(document.pages.single.rawImagePath, isNull);
    expect(document.pages.single.thumbnailPath, isNull);
    expect(document.pages.single.corners, isNull);
    expect(document.pages.single.rotationAngle, 0);
    expect(document.pages.single.ocrResult, isNull);
    expect(document.pages.single.isDirty, isFalse);
    expect(documentRow['favorite'], 0);
    expect(documentRow['tags_json'], '[]');
    expect(pageRow['crop_transform_json'], '{}');
  });

  test('all supported legacy filters migrate without enum ordinals', () async {
    final filters = ['auto', 'magic', 'original', 'smart', 'gray', 'bw'];
    final databasePath = await temporaryPath('filters');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-filters', [
        for (var i = 0; i < filters.length; i++)
          legacyPage('filter-$i', i, filter: filters[i]),
      ]),
    ]);

    final database = ScanoraDatabase(databasePath: databasePath);
    addTearDown(database.close);
    final document = await SqliteDocumentRepositoryV2(
      database: database,
    ).getById('doc-filters');

    expect(document!.pages.map((page) => page.filterType), [
      ScanFilterType.auto,
      ScanFilterType.magic,
      ScanFilterType.original,
      ScanFilterType.smart,
      ScanFilterType.gray,
      ScanFilterType.blackAndWhite,
    ]);
  });

  test(
    'actual v2 schema has keys, indexes, foreign key, and cascade behavior',
    () async {
      final databasePath = await temporaryPath('schema');
      addTearDown(() => cleanup(databasePath));
      await createLegacyDatabase(databasePath, [
        legacyDocument('doc-schema', [legacyPage('page-1', 0)]),
      ]);
      final database = ScanoraDatabase(databasePath: databasePath);
      addTearDown(database.close);
      await database.openAt(databasePath);
      final db = await database.open();

      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      final pageForeignKeys = await db.rawQuery(
        'PRAGMA foreign_key_list(pages)',
      );
      expect(pageForeignKeys.single['table'], 'documents');
      expect(pageForeignKeys.single['on_delete'], 'CASCADE');
      final documentIndexes = await db.rawQuery('PRAGMA index_list(documents)');
      final pageIndexes = await db.rawQuery('PRAGMA index_list(pages)');
      expect(
        documentIndexes.any((row) => row['name'] == 'idx_documents_updated_at'),
        isTrue,
      );
      expect(
        pageIndexes.any((row) => row['name'] == 'idx_pages_document_index'),
        isTrue,
      );
      final uniqueIndexes = pageIndexes.where((row) => row['unique'] == 1);
      expect(uniqueIndexes, isNotEmpty);
      final uniqueIndexInfo = await db.rawQuery(
        'PRAGMA index_info(${uniqueIndexes.first['name']})',
      );
      expect(
        uniqueIndexInfo.map((row) => row['name']),
        containsAll(['document_id', 'page_index']),
      );

      await db.delete('documents', where: 'id = ?', whereArgs: ['doc-schema']);
      expect(await db.query('pages'), isEmpty);
    },
  );

  test(
    'failed migration rolls back schema and data, then retry succeeds',
    () async {
      final databasePath = await temporaryPath('rollback');
      addTearDown(() => cleanup(databasePath));
      await createLegacyDatabase(databasePath, [
        legacyDocument('doc-good', [legacyPage('good-page', 0)]),
        legacyDocument('doc-bad', [
          legacyPage('bad-page', 0),
        ], createdAt: 'not-a-date'),
      ]);

      final failed = ScanoraDatabase(databasePath: databasePath);
      expect(
        () => SqliteDocumentRepositoryV2(database: failed).getAll(),
        throwsA(isA<Exception>()),
      );
      await failed.close();

      final inspect = await databaseFactoryFfi.openDatabase(databasePath);
      expect(
        (await inspect.rawQuery('PRAGMA user_version')).single.values.single,
        1,
      );
      expect(
        (await inspect.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'pages'",
        )).isEmpty,
        isTrue,
      );
      expect((await inspect.query('documents')).length, 2);
      await inspect.update(
        'documents',
        {'createdAt': timestamp},
        where: 'id = ?',
        whereArgs: ['doc-bad'],
      );
      await inspect.close();

      final retry = ScanoraDatabase(databasePath: databasePath);
      addTearDown(retry.close);
      final documents =
          await SqliteDocumentRepositoryV2(database: retry).getAll();
      expect(documents.length, 2);
      expect(await (await retry.open()).getVersion(), 3);
    },
  );

  test('reopening v2 does not rerun migration or duplicate rows', () async {
    final databasePath = await temporaryPath('retry');
    addTearDown(() => cleanup(databasePath));
    await createLegacyDatabase(databasePath, [
      legacyDocument('doc-1', [legacyPage('page-1', 0)]),
    ]);

    final first = ScanoraDatabase(databasePath: databasePath);
    addTearDown(first.close);
    final firstRepository = SqliteDocumentRepositoryV2(database: first);
    await firstRepository.getAll();
    await first.close();
    final second = ScanoraDatabase(databasePath: databasePath);
    addTearDown(second.close);
    final secondRepository = SqliteDocumentRepositoryV2(database: second);
    expect((await secondRepository.getAll()).single.pages.length, 1);
    final db = await second.open();
    expect((await db.query('documents')).length, 1);
    expect((await db.query('pages')).length, 1);
    expect(await db.getVersion(), 3);
  });
}
