from __future__ import annotations

# JPEG markers matching `lib/data/services/exif_stripper.dart`
_JPEG_SOI = (0xFF, 0xD8)
_MARKER_EOI = 0xD9
_MARKER_SOS = 0xDA
_MARKER_TEM = 0x01
_RST0 = 0xD0
_RST7 = 0xD7

# Segments stripped for Privacy-by-Design:
# - 0xE1: APP1 (EXIF, GPS coordinates, device make/model, XMP)
# - 0xE2: APP2 (ICC profile / extended EXIF)
# - 0xED: APP13 (IPTC)
# - 0xFE: COM (JPEG comments)
STRIPPED_MARKERS: frozenset[int] = frozenset({0xE1, 0xE2, 0xED, 0xFE})


def has_exif_or_metadata_markers(data: bytes) -> bool:
    """Return True if a JPEG buffer contains any APP1, APP2, APP13, or COM marker."""
    if len(data) < 4 or data[0] != _JPEG_SOI[0] or data[1] != _JPEG_SOI[1]:
        return False

    i = 2
    n = len(data)
    while i + 1 < n:
        if data[i] != 0xFF:
            return False
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            return False

        marker = data[i]
        i += 1

        if marker in (_MARKER_EOI, _MARKER_SOS):
            return False
        if (_RST0 <= marker <= _RST7) or marker == _MARKER_TEM:
            continue

        if i + 1 >= n:
            return False
        segment_length = (data[i] << 8) | data[i + 1]
        if segment_length < 2 or i + segment_length > n:
            return False

        if marker in STRIPPED_MARKERS:
            return True

        i += segment_length

    return False


def strip_jpeg_metadata(data: bytes) -> bytes:
    """Strip EXIF/GPS/XMP/IPTC/COM metadata segments from a JPEG byte buffer.

    Mirrors `ExifStripper.stripJpegMetadata` in `lib/data/services/exif_stripper.dart`.
    Non-JPEG buffers (such as PNG) or malformed byte sequences are returned unchanged.
    """
    if len(data) < 4 or data[0] != _JPEG_SOI[0] or data[1] != _JPEG_SOI[1]:
        return data

    out = bytearray()
    out.extend(_JPEG_SOI)

    i = 2
    n = len(data)
    while i + 1 < n:
        if data[i] != 0xFF:
            # Unexpected non-marker before SOS; preserve original bytes safely.
            return data
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            break

        marker = data[i]
        i += 1

        # End of Image (EOI)
        if marker == _MARKER_EOI:
            out.append(0xFF)
            out.append(_MARKER_EOI)
            break

        # Start of Scan (SOS) — copy entropy-coded payload verbatim
        if marker == _MARKER_SOS:
            out.append(0xFF)
            out.append(_MARKER_SOS)
            out.extend(data[i:])
            return bytes(out)

        # Standalone markers without length field (RST0-RST7, TEM)
        if (_RST0 <= marker <= _RST7) or marker == _MARKER_TEM:
            out.append(0xFF)
            out.append(marker)
            continue

        if i + 1 >= n:
            return data
        segment_length = (data[i] << 8) | data[i + 1]
        if segment_length < 2 or i + segment_length > n:
            return data

        if marker not in STRIPPED_MARKERS:
            out.append(0xFF)
            out.append(marker)
            out.extend(data[i : i + segment_length])

        i += segment_length

    return bytes(out)
