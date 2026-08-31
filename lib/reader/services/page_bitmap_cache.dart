import 'dart:collection';
import 'dart:ui';

/// Identifies one rendered PDF bitmap.
///
/// Geometry is part of the key because the same page may be rendered at
/// different sizes and crop rectangles as the reader mode changes.
class PdfBitmapCacheKey {
  final int pageIndex;
  final int pixelWidth;
  final int pixelHeight;
  final int rotationQuarterTurns;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  const PdfBitmapCacheKey({
    required this.pageIndex,
    required this.pixelWidth,
    required this.pixelHeight,
    this.rotationQuarterTurns = 0,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfBitmapCacheKey &&
          pageIndex == other.pageIndex &&
          pixelWidth == other.pixelWidth &&
          pixelHeight == other.pixelHeight &&
          rotationQuarterTurns == other.rotationQuarterTurns &&
          cropLeft == other.cropLeft &&
          cropTop == other.cropTop &&
          cropRight == other.cropRight &&
          cropBottom == other.cropBottom;

  @override
  int get hashCode => Object.hash(
    pageIndex,
    pixelWidth,
    pixelHeight,
    rotationQuarterTurns,
    cropLeft,
    cropTop,
    cropRight,
    cropBottom,
  );
}

/// Memory-bounded least-recently-used cache for rendered PDF pages.
///
/// A bitmap accepted by [put] is owned by the cache and is disposed when it is
/// replaced, evicted, or [clear] is called. A bitmap larger than [maxBytes] is
/// rejected and remains owned by the caller.
class PageBitmapCache {
  static const int defaultMaxBytes = 40 * 1024 * 1024;

  int _maxBytes;
  final LinkedHashMap<PdfBitmapCacheKey, Image> _images = LinkedHashMap();
  int _currentBytes = 0;

  PageBitmapCache({int maxBytes = defaultMaxBytes})
    : assert(maxBytes > 0),
      _maxBytes = maxBytes;

  int get maxBytes => _maxBytes;

  /// Applies a runtime budget, immediately releasing least-recently-used images.
  void resize(int maxBytes) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    _maxBytes = maxBytes;
    _evictToBudget();
  }

  int get currentBytes => _currentBytes;
  int get length => _images.length;
  bool get isEmpty => _images.isEmpty;

  Image? get(PdfBitmapCacheKey key) {
    final image = _images.remove(key);
    if (image != null) {
      // Reinsertion makes this the most recently used item.
      _images[key] = image;
    }
    return image;
  }

  bool containsKey(PdfBitmapCacheKey key) => _images.containsKey(key);

  /// Adds [image] to the cache and returns whether the cache accepted it.
  bool put(PdfBitmapCacheKey key, Image image) {
    final imageBytes = _byteSize(image);
    if (imageBytes > maxBytes) return false;

    final previous = _images.remove(key);
    if (identical(previous, image)) {
      _images[key] = image;
      return true;
    }
    if (previous != null) {
      _currentBytes -= _byteSize(previous);
      previous.dispose();
    }

    _images[key] = image;
    _currentBytes += imageBytes;
    _evictToBudget();
    return true;
  }

  void remove(PdfBitmapCacheKey key) {
    final image = _images.remove(key);
    if (image == null) return;
    _currentBytes -= _byteSize(image);
    image.dispose();
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _currentBytes = 0;
  }

  void _evictToBudget() {
    while (_currentBytes > maxBytes && _images.isNotEmpty) {
      final oldestKey = _images.keys.first;
      remove(oldestKey);
    }
  }

  static int _byteSize(Image image) => image.width * image.height * 4;
}
