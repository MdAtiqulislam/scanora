import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_failure.dart';
import '../models/scanned_page.dart';

class ScanoraDatabase {
  static const databaseName = 'scanora.db';
  static const version = 3;
  static const documentsTable = 'documents';
  static const pagesTable = 'pages';

  Database? _database;
  final String? databasePath;

  ScanoraDatabase({this.databasePath});

  Future<Database> open() async {
    if (_database != null && _database!.isOpen) return _database!;
    final databasesPath = await getDatabasesPath();
    return openAt(databasePath ?? path.join(databasesPath, databaseName));
  }

  Future<Database> openAt(String databasePath) async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await openDatabase(
      databasePath,
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) => createV2Schema(db),
      onUpgrade: migrate,
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  static Future<void> createV2Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
        tags_json TEXT NOT NULL DEFAULT '[]',
        pdf_path TEXT,
        page_count INTEGER NOT NULL DEFAULT 0 CHECK (page_count >= 0)
      )
    ''');
    await db.execute('''
      CREATE TABLE pages (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_index INTEGER NOT NULL CHECK (page_index >= 0),
        raw_image_path TEXT,
        processed_image_path TEXT,
        thumbnail_path TEXT,
        corners_json TEXT,
        rotation_angle REAL NOT NULL DEFAULT 0,
        crop_transform_json TEXT NOT NULL DEFAULT '{}',
        processing_profile_json TEXT NOT NULL DEFAULT '{}',
        ocr_result TEXT,
        is_dirty INTEGER NOT NULL DEFAULT 0 CHECK (is_dirty IN (0, 1)),
        processed_cache_key TEXT,
        thumbnail_cache_key TEXT,
        edit_state_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
        UNIQUE (document_id, page_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_documents_updated_at ON documents(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_pages_document_index ON pages(document_id, page_index)',
    );
  }

  /// Migrates the only shipped legacy schema (version 1) in the same SQLite
  /// upgrade transaction supplied by sqflite. The old JSON column is retained
  /// as inert compatibility data; v2 reads and writes normalized page rows.
  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1 || oldVersion > version) {
      throw const StorageFailure('Unsupported Scanora database version');
    }
    if (oldVersion < 2) await _migrateV1ToV2(db);
    if (oldVersion < 3) await _migrateV2ToV3(db);
  }

  static Future<void> _migrateV2ToV3(Database db) async {
    await db.execute('ALTER TABLE pages ADD COLUMN processed_cache_key TEXT');
    await db.execute('ALTER TABLE pages ADD COLUMN thumbnail_cache_key TEXT');
    await db.execute(
      'ALTER TABLE pages ADD COLUMN edit_state_version INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> _migrateV1ToV2(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(documents)');
    final existing = columns.map((row) => row['name'] as String).toSet();
    Future<void> add(String definition, String name) async {
      if (!existing.contains(name)) {
        await db.execute('ALTER TABLE documents ADD COLUMN $definition');
      }
    }

    await add('created_at TEXT', 'created_at');
    await add('updated_at TEXT', 'updated_at');
    await add('favorite INTEGER NOT NULL DEFAULT 0', 'favorite');
    await add("tags_json TEXT NOT NULL DEFAULT '[]'", 'tags_json');
    await add('page_count INTEGER NOT NULL DEFAULT 0', 'page_count');
    await db.execute('ALTER TABLE documents ADD COLUMN pdf_path TEXT');

    await db.execute('''
      CREATE TABLE pages (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_index INTEGER NOT NULL CHECK (page_index >= 0),
        raw_image_path TEXT,
        processed_image_path TEXT,
        thumbnail_path TEXT,
        corners_json TEXT,
        rotation_angle REAL NOT NULL DEFAULT 0,
        crop_transform_json TEXT NOT NULL DEFAULT '{}',
        processing_profile_json TEXT NOT NULL DEFAULT '{}',
        ocr_result TEXT,
        is_dirty INTEGER NOT NULL DEFAULT 0 CHECK (is_dirty IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
        UNIQUE (document_id, page_index)
      )
    ''');

    final rows = await db.query('documents');
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) {
        throw const StorageFailure('Legacy document has no valid id');
      }
      final created = _legacyDate(row['createdAt']);
      final updated = _legacyDate(row['updatedAt']);
      await db.update(
        'documents',
        {
          'created_at': created,
          'updated_at': updated,
          'pdf_path': row['pdfPath'],
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final rawPages = row['pages']?.toString() ?? '[]';
      final decoded = jsonDecode(rawPages);
      if (decoded is! List) {
        throw StorageFailure('Legacy pages value is not a list for $id');
      }
      final reservedPageIds =
          decoded
              .whereType<Map>()
              .map((value) => value['id']?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toSet();
      for (var index = 0; index < decoded.length; index++) {
        final value = decoded[index];
        if (value is! Map) {
          throw StorageFailure('Invalid legacy page $index for document $id');
        }
        final page = ScannedPage.fromMap(value.cast<String, dynamic>());
        final pageId = await _migrationPageId(
          db,
          id,
          page.id,
          index,
          reservedPageIds,
        );
        reservedPageIds.add(pageId);
        final createdAt = page.createdAt.toIso8601String();
        final filterType = switch (page.filter) {
          'original' => 'original',
          'auto' => 'auto',
          'magic' => 'magic',
          'gray' => 'gray',
          'blackAndWhite' => 'blackAndWhite',
          'bw' => 'blackAndWhite',
          _ => 'smart',
        };
        await db.insert('pages', {
          'id': pageId,
          'document_id': id,
          'page_index': index,
          'raw_image_path':
              page.rawImagePath?.isEmpty == true ? null : page.rawImagePath,
          'processed_image_path': page.imagePath,
          'thumbnail_path': null,
          'corners_json': null,
          'rotation_angle': 0,
          'crop_transform_json': '{}',
          'processing_profile_json': jsonEncode({'filterType': filterType}),
          'ocr_result': null,
          'is_dirty': 0,
          'created_at': createdAt,
          'updated_at': createdAt,
        });
      }
      await db.update(
        'documents',
        {'page_count': decoded.length},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await db.execute(
      'CREATE INDEX idx_documents_updated_at ON documents(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_pages_document_index ON pages(document_id, page_index)',
    );
  }

  static String _legacyDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const StorageFailure('Legacy document has an invalid timestamp');
    }
    return parsed.toIso8601String();
  }

  static Future<String> _migrationPageId(
    Database db,
    String documentId,
    String legacyId,
    int pageIndex,
    Set<String> reservedPageIds,
  ) async {
    if (legacyId.isNotEmpty) return legacyId;
    final base = '$documentId-page-$pageIndex';
    var candidate = base;
    var suffix = 0;
    while (reservedPageIds.contains(candidate) ||
        (await db.query(
          'pages',
          where: 'id = ?',
          whereArgs: [candidate],
        )).isNotEmpty) {
      suffix++;
      candidate = '$base-migrated-$suffix';
    }
    return candidate;
  }
}
