import 'dart:typed_data';

/// Pure-Dart JPEG metadata stripper for Privacy-by-Design (`hackathonshow.md §6`).
///
/// Removes hidden camera metadata segments (`APP1` EXIF/GPS/camera model/XMP,
/// `APP2` ICC/extended EXIF, and `COM` comments) while keeping the encoded
/// image frames (`SOF`, `DHT`, `DQT`, `SOS`, and compressed scan data) intact.
///
/// Always run after `ImagePicker` has resized/baked upright orientation
/// (`maxWidth` / `imageQuality`) so portrait photos stay upright.
abstract final class ExifStripper {
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
