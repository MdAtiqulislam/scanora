import 'dart:typed_data';

import '../../domain/geometry/geometry_models.dart';

/// Fast JPEG SOF-marker dimension parser.
/// Scans the JPEG byte stream for Start-of-Frame markers and extracts
/// width/height without decoding the full image.
///
/// Extracted from DocumentPageProcessingService to allow shared usage
/// across layers without creating architecture violations.
PixelSize? parseJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset < bytes.length - 1) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    offset += 2;
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x00 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (offset + 2 > bytes.length) break;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) break;

    if ((marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF)) {
      if (length >= 7) {
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        return PixelSize(width, height);
      }
    }
    offset += length;
  }
  return null;
}
