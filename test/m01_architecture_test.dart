import 'package:flutter_test/flutter_test.dart';
import 'package:scanora/app/domain/entities/scan_document.dart';
import 'package:scanora/app/domain/entities/scan_page.dart';
import 'package:scanora/app/domain/enums/scan_enums.dart';
import 'package:scanora/app/domain/value_objects/page_corners.dart';
import 'package:scanora/app/domain/value_objects/processing_profile.dart';
import 'package:scanora/app/domain/value_objects/point.dart';
import 'package:scanora/app/data/models/scanned_document.dart' as legacy;
import 'package:scanora/app/data/models/scanned_page.dart' as legacy_page;

void main() {
  final timestamp = DateTime(2026, 1, 1);

  test('ScanDocument exposes v2 document concepts', () {
    final document = ScanDocument(
      id: 'document-1',
      title: 'Receipt',
      createdAt: timestamp,
      updatedAt: timestamp,
      favorite: true,
      tags: const ['finance'],
      pages: [
        ScanPage(
          id: 'page-1',
          documentId: 'document-1',
          pageIndex: 0,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
    );

    expect(document.pageCount, 1);
    expect(document.favorite, isTrue);
  });

  test('PageCorners validates finite, distinct points', () {
    expect(
      () => PageCorners(
        topLeft: const Point2D(0, 0),
        topRight: const Point2D(1, 0),
        bottomRight: const Point2D(1, 1),
        bottomLeft: const Point2D(0, 1),
      ),
      returnsNormally,
    );
    expect(
      () => PageCorners(
        topLeft: const Point2D(0, 0),
        topRight: const Point2D(0, 0),
        bottomRight: const Point2D(1, 1),
        bottomLeft: const Point2D(0, 1),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('ProcessingProfile round trips independently from rendered assets', () {
    const profile = ProcessingProfile(filterType: ScanFilterType.blackAndWhite);
    final restored = ProcessingProfile.fromMap(profile.toMap());

    expect(restored.filterType, ScanFilterType.blackAndWhite);
    expect(restored.adjustments.brightness, 0);
  });

  test('domain enums expose the locked filter concepts', () {
    expect(
      ScanFilterType.values.map((value) => value.name),
      containsAll(['original', 'color', 'smart', 'gray', 'blackAndWhite']),
    );
    expect(CaptureSource.values, contains(CaptureSource.nativeScanner));
  });

  test('legacy document serialization remains round-trip compatible', () {
    final document = legacy.ScannedDocument(
      id: 'legacy-1',
      title: 'Legacy',
      pages: [
        legacy_page.ScannedPage(id: 'page-1', imagePath: '/tmp/page.jpg'),
      ],
      pdfPath: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final restored = legacy.ScannedDocument.fromJson(document.toJson());
    expect(restored.id, document.id);
    expect(restored.pages.single.imagePath, '/tmp/page.jpg');
    expect(restored.pdfPath, isNull);
  });
}
