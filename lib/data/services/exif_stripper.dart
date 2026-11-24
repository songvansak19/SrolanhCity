import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

/// Camera GPS & capture timestamp extracted in-memory BEFORE EXIF stripping.
///
/// Used purely for anti-spoof cross-checking (`AntiSpoofService.evaluatePhotoExif`)
/// while the persisted/uploaded image bytes remain 100% EXIF-free.
class PhotoExifMetadata {
  const PhotoExifMetadata({this.coordinates, this.capturedAt});

  final LatLng? coordinates;
  final DateTime? capturedAt;

  bool get hasCoordinates => coordinates != null;
  bool get hasCapturedAt => capturedAt != null;
  bool get isEmpty => coordinates == null && capturedAt == null;
}

/// Pure-Dart JPEG metadata extractor & stripper for Privacy-by-Design
/// (`hackathonshow.md §6`).
///
/// - [extractJpegMetadata] reads optional GPS coordinates and `DateTimeOriginal`
///   from JPEG `APP1` (`Exif\0\0`) blocks (both little-endian `II` and
///   big-endian `MM` TIFF headers) without throwing on malformed/non-JPEG data.
/// - [stripJpegMetadata] removes hidden camera metadata segments (`APP1`
///   EXIF/GPS/camera model/XMP, `APP2` ICC/extended EXIF, `APP13` IPTC, and
///   `COM` comments) while keeping the encoded image frames intact.
abstract final class ExifStripper {
  /// Extracts pre-strip GPS coordinates and capture timestamp from a JPEG
  /// buffer. Safely returns an empty [PhotoExifMetadata] on PNGs, stripped
  /// JPEGs, or malformed files.
  static PhotoExifMetadata extractJpegMetadata(Uint8List bytes) {
    try {
      if (bytes.length < 16 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        return const PhotoExifMetadata();
      }

      var i = 2;
      while (i + 3 < bytes.length) {
        if (bytes[i] != 0xFF) break;
        while (i < bytes.length && bytes[i] == 0xFF) {
          i++;
        }
        if (i >= bytes.length) break;

        final marker = bytes[i];
        i++;

        if (marker == 0xD9 || marker == 0xDA) break;
        if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) continue;

        if (i + 1 >= bytes.length) break;
        final segmentLength = (bytes[i] << 8) | bytes[i + 1];
        if (segmentLength < 2 || i + segmentLength > bytes.length) break;

        if (marker == 0xE1 && segmentLength >= 16) {
          final payloadStart = i + 2;
          final payloadEnd = i + segmentLength;
          // Check "Exif\0\0" header.
          if (payloadStart + 14 <= payloadEnd &&
              bytes[payloadStart] == 0x45 &&
              bytes[payloadStart + 1] == 0x78 &&
              bytes[payloadStart + 2] == 0x69 &&
              bytes[payloadStart + 3] == 0x66 &&
              bytes[payloadStart + 4] == 0x00 &&
              bytes[payloadStart + 5] == 0x00) {
            final tiffStart = payloadStart + 6;
            final parsed = _parseTiff(bytes, tiffStart, payloadEnd);
            if (!parsed.isEmpty) {
              return parsed;
            }
          }
        }

        i += segmentLength;
      }
    } catch (_) {
      // Never crash photo import on corrupted EXIF blocks.
    }
    return const PhotoExifMetadata();
  }

  static PhotoExifMetadata _parseTiff(
    Uint8List bytes,
    int tiffStart,
    int limit,
  ) {
    if (tiffStart + 8 > limit) return const PhotoExifMetadata();
    final isLittleEndian =
        bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final isBigEndian =
        bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
    if (!isLittleEndian && !isBigEndian) return const PhotoExifMetadata();

    final endian = isLittleEndian ? Endian.little : Endian.big;
    final data = ByteData.sublistView(bytes, tiffStart, limit);
    if (data.getUint16(2, endian) != 0x002A) return const PhotoExifMetadata();

    final ifd0Offset = data.getUint32(4, endian);
    if (ifd0Offset < 8 || ifd0Offset + 2 > data.lengthInBytes) {
      return const PhotoExifMetadata();
    }

    int? exifIfdOffset;
    int? gpsIfdOffset;
    DateTime? ifd0Date;

    _visitIfd(data, ifd0Offset, endian, (tag, type, count, valueOffset) {
      if (tag == 0x8769 && count >= 1) {
        exifIfdOffset = _readOffsetPointer(data, type, valueOffset, endian);
      } else if (tag == 0x8825 && count >= 1) {
        gpsIfdOffset = _readOffsetPointer(data, type, valueOffset, endian);
      } else if (tag == 0x0132 && type == 2) {
        ifd0Date ??= _parseExifDate(
          _readAscii(data, count, valueOffset, endian),
        );
      }
    });

    DateTime? capturedAt;
    if (exifIfdOffset != null) {
      DateTime? original;
      DateTime? digitized;
      _visitIfd(data, exifIfdOffset!, endian, (tag, type, count, valueOffset) {
        if (type != 2) return;
        if (tag == 0x9003) {
          original ??= _parseExifDate(
            _readAscii(data, count, valueOffset, endian),
          );
        } else if (tag == 0x9004) {
          digitized ??= _parseExifDate(
            _readAscii(data, count, valueOffset, endian),
          );
        }
      });
      capturedAt = original ?? digitized ?? ifd0Date;
    } else {
      capturedAt = ifd0Date;
    }

    LatLng? coordinates;
    if (gpsIfdOffset != null) {
      String? latRef;
      String? lngRef;
      double? latAbs;
      double? lngAbs;
      _visitIfd(data, gpsIfdOffset!, endian, (tag, type, count, valueOffset) {
        if (tag == 0x0001 && type == 2) {
          latRef = _readAscii(data, count, valueOffset, endian).trim();
        } else if (tag == 0x0002 && type == 5 && count >= 3) {
          latAbs = _readDmsRational(data, valueOffset, endian);
        } else if (tag == 0x0003 && type == 2) {
          lngRef = _readAscii(data, count, valueOffset, endian).trim();
        } else if (tag == 0x0004 && type == 5 && count >= 3) {
          lngAbs = _readDmsRational(data, valueOffset, endian);
        }
      });

      if (latAbs != null && lngAbs != null) {
        final lat = (latRef?.toUpperCase() == 'S') ? -latAbs! : latAbs!;
        final lng = (lngRef?.toUpperCase() == 'W') ? -lngAbs! : lngAbs!;
        if (lat.isFinite &&
            lng.isFinite &&
            lat >= -90 &&
            lat <= 90 &&
            lng >= -180 &&
            lng <= 180 &&
            !(lat.abs() < 0.0001 && lng.abs() < 0.0001)) {
          coordinates = LatLng(lat, lng);
        }
      }
    }

    return PhotoExifMetadata(coordinates: coordinates, capturedAt: capturedAt);
  }

  static void _visitIfd(
    ByteData data,
    int ifdOffset,
    Endian endian,
    void Function(int tag, int type, int count, int valueFieldOffset) visitor,
  ) {
    if (ifdOffset < 0 || ifdOffset + 2 > data.lengthInBytes) return;
    final entryCount = data.getUint16(ifdOffset, endian);
    var cursor = ifdOffset + 2;
    for (var idx = 0; idx < entryCount; idx++) {
      if (cursor + 12 > data.lengthInBytes) break;
      final tag = data.getUint16(cursor, endian);
      final type = data.getUint16(cursor + 2, endian);
      final count = data.getUint32(cursor + 4, endian);
      visitor(tag, type, count, cursor + 8);
      cursor += 12;
    }
  }

  static int? _readOffsetPointer(
    ByteData data,
    int type,
    int valueFieldOffset,
    Endian endian,
  ) {
    if (valueFieldOffset + 4 > data.lengthInBytes) return null;
    if (type == 4 || type == 13) {
      return data.getUint32(valueFieldOffset, endian);
    }
    if (type == 3) {
      return data.getUint16(valueFieldOffset, endian);
    }
    return null;
  }

  static String _readAscii(
    ByteData data,
    int count,
    int valueFieldOffset,
    Endian endian,
  ) {
    if (count <= 0 || count > 128) return '';
    final int start;
    if (count <= 4) {
      start = valueFieldOffset;
    } else {
      if (valueFieldOffset + 4 > data.lengthInBytes) return '';
      start = data.getUint32(valueFieldOffset, endian);
    }
    if (start < 0 || start + count > data.lengthInBytes) return '';
    final codes = <int>[];
    for (var i = 0; i < count; i++) {
      final byte = data.getUint8(start + i);
      if (byte == 0) break;
      codes.add(byte);
    }
    return String.fromCharCodes(codes);
  }

  static double? _readDmsRational(
    ByteData data,
    int valueFieldOffset,
    Endian endian,
  ) {
    if (valueFieldOffset + 4 > data.lengthInBytes) return null;
    final offset = data.getUint32(valueFieldOffset, endian);
    if (offset < 0 || offset + 24 > data.lengthInBytes) return null;

    double? readRational(int pos) {
      final num = data.getUint32(pos, endian);
      final den = data.getUint32(pos + 4, endian);
      if (den == 0) return null;
      return num / den;
    }

    final deg = readRational(offset);
    final min = readRational(offset + 8);
    final sec = readRational(offset + 16);
    if (deg == null || min == null || sec == null) return null;
    return deg + (min / 60.0) + (sec / 3600.0);
  }

  static DateTime? _parseExifDate(String raw) {
    // Standard EXIF format: "YYYY:MM:DD HH:MM:SS"
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6)!);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null ||
        year < 1990 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  /// Strips metadata markers from a JPEG byte buffer.
  ///
  /// Non-JPEG buffers (such as PNG) or malformed inputs are returned safely
  /// without throwing or corrupting the image.
  static Uint8List stripJpegMetadata(Uint8List bytes) {
    // JPEG must start with SOI (0xFF 0xD8).
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return bytes;
    }

    final out = BytesBuilder(copy: false);
    out.addByte(0xFF);
    out.addByte(0xD8);

    var i = 2;
    while (i + 1 < bytes.length) {
      // Skip any 0xFF padding bytes before a marker.
      if (bytes[i] != 0xFF) {
        // Unexpected non-marker before SOS; preserve original bytes safely.
        return bytes;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;

      final marker = bytes[i];
      i++;

      // End of Image (EOI).
      if (marker == 0xD9) {
        out.addByte(0xFF);
        out.addByte(0xD9);
        break;
      }

      // Start of Scan (SOS) — copy the rest of the entropy-coded image verbatim.
      if (marker == 0xDA) {
        out.addByte(0xFF);
        out.addByte(0xDA);
        out.add(bytes.sublist(i));
        return out.toBytes();
      }

      // Standalone markers without a length payload (RST0–RST7, TEM).
      if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        out.addByte(0xFF);
        out.addByte(marker);
        continue;
      }

      // All other markers carry a big-endian 2-byte length (including the 2 bytes).
      if (i + 1 >= bytes.length) {
        return bytes;
      }
      final segmentLength = (bytes[i] << 8) | bytes[i + 1];
      if (segmentLength < 2 || i + segmentLength > bytes.length) {
        return bytes;
      }

      // Drop APP1 (0xE1: EXIF/GPS/XMP), APP2 (0xE2), APP13 (0xED: IPTC),
      // and COM (0xFE: comments). Keep APP0 (JFIF), DQT, DHT, SOF, DRI, etc.
      final shouldStrip =
          marker == 0xE1 || marker == 0xE2 || marker == 0xED || marker == 0xFE;

      if (!shouldStrip) {
        out.addByte(0xFF);
        out.addByte(marker);
        out.add(bytes.sublist(i, i + segmentLength));
      }

      i += segmentLength;
    }

    return out.toBytes();
  }
}
