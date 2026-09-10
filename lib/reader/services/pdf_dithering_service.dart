import 'dart:isolate';
import 'dart:typed_data';

/// Optional ordered quantization to 16 levels (per channel in color mode).
/// This is a generic e-ink transform, not a device palette calibration.
class PdfDitheringService {
  static Future<Uint8List> transform(
    Uint8List pixels,
    int width,
    int height, {
    required bool colorEnabled,
    int originX = 0,
    int originY = 0,
  }) {
    // Native PDFium storage must never be accessed by the worker after disposal.
    final owned = Uint8List.fromList(pixels);
    return Isolate.run(
      () => transformSync(
        owned,
        width,
        height,
        colorEnabled: colorEnabled,
        originX: originX,
        originY: originY,
      ),
    );
  }

  static Uint8List transformSync(
    Uint8List pixels,
    int width,
    int height, {
    required bool colorEnabled,
    int originX = 0,
    int originY = 0,
  }) {
    if (width <= 0 || height <= 0 || pixels.length != width * height * 4) {
      throw ArgumentError('Invalid BGRA image dimensions');
    }
    const bayer = [
      0,
      48,
      12,
      60,
      3,
      51,
      15,
      63,
      32,
      16,
      44,
      28,
      35,
      19,
      47,
      31,
      8,
      56,
      4,
      52,
      11,
      59,
      7,
      55,
      40,
      24,
      36,
      20,
      43,
      27,
      39,
      23,
      2,
      50,
      14,
      62,
      1,
      49,
      13,
      61,
      34,
      18,
      46,
      30,
      33,
      17,
      45,
      29,
      10,
      58,
      6,
      54,
      9,
      57,
      5,
      53,
      42,
      26,
      38,
      22,
      41,
      25,
      37,
      21,
    ];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        // PDF renders are opaque by default. Preserve premultiplied pixels
        // for unusual transparent renders instead of introducing alpha fringes.
        if (pixels[i + 3] != 255) continue;
        final threshold = bayer[((y + originY) & 7) * 8 + ((x + originX) & 7)];
        int quantize(int value) {
          final base = value ~/ 17;
          final up = (value % 17) * 128 > (threshold * 2 + 1) * 17;
          return ((base + (up ? 1 : 0)) * 17).clamp(0, 255);
        }

        if (colorEnabled) {
          for (var c = 0; c < 3; c++) {
            pixels[i + c] = quantize(pixels[i + c]);
          }
        } else {
          final gray = quantize(
            (pixels[i + 2] * 77 + pixels[i + 1] * 150 + pixels[i] * 29 + 128) >>
                8,
          );
          pixels[i] = pixels[i + 1] = pixels[i + 2] = gray;
        }
      }
    }
    return pixels;
  }
}
