import 'bookmark.dart';
import 'doc_ref.dart';
import 'reader_settings.dart';
import 'reading_position.dart';

class BookState {
  final String docId;
  final String lastPath;
  final DocFormat format;
  final DateTime lastRead;
  final ReadingPosition position;
  final double percent;
  final ReaderSettings? settingsOverride;
  final List<Bookmark> bookmarks;

  /// pageIndex -> [left, top, right, bottom] normalized fractions.
  final Map<int, List<double>> cachedCropRects;
  final List<double>? uniformPdfCrop;

  const BookState({
    required this.docId,
    required this.lastPath,
    required this.format,
    required this.lastRead,
    required this.position,
    this.percent = 0.0,
    this.settingsOverride,
    this.bookmarks = const [],
    this.cachedCropRects = const {},
    this.uniformPdfCrop,
  });

  BookState copyWith({
    String? lastPath,
    DateTime? lastRead,
    ReadingPosition? position,
    double? percent,
    ReaderSettings? settingsOverride,
    List<Bookmark>? bookmarks,
    Map<int, List<double>>? cachedCropRects,
    List<double>? uniformPdfCrop,
  }) {
    return BookState(
      docId: docId,
      lastPath: lastPath ?? this.lastPath,
      format: format,
      lastRead: lastRead ?? this.lastRead,
      position: position ?? this.position,
      percent: percent ?? this.percent,
      settingsOverride: settingsOverride ?? this.settingsOverride,
      bookmarks: bookmarks ?? this.bookmarks,
      cachedCropRects: cachedCropRects ?? this.cachedCropRects,
      uniformPdfCrop: uniformPdfCrop ?? this.uniformPdfCrop,
    );
  }

  Map<String, dynamic> toJson() => {
    'docId': docId,
    'lastPath': lastPath,
    'format': format.name,
    'lastRead': lastRead.toIso8601String(),
    'position': position.toJson(),
    'percent': percent,
    if (settingsOverride != null)
      'settingsOverride': settingsOverride!.toJson(),
    if (bookmarks.isNotEmpty)
      'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    if (cachedCropRects.isNotEmpty)
      'cachedCropRects': cachedCropRects.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
    if (uniformPdfCrop != null) 'uniformPdfCrop': uniformPdfCrop,
  };

  factory BookState.fromJson(Map<String, dynamic> json) => BookState(
    docId: json['docId'] as String,
    lastPath: json['lastPath'] as String,
    format: DocFormat.values.byName(json['format'] as String),
    lastRead: DateTime.parse(json['lastRead'] as String),
    position: ReadingPosition.fromJson(
      json['position'] as Map<String, dynamic>,
    ),
    percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
    settingsOverride: json['settingsOverride'] != null
        ? ReaderSettings.fromJson(
            json['settingsOverride'] as Map<String, dynamic>,
          )
        : null,
    bookmarks:
        (json['bookmarks'] as List<dynamic>?)
            ?.map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
            .toList() ??
        const [],
    cachedCropRects:
        (json['cachedCropRects'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(
            int.parse(k),
            (v as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
          ),
        ) ??
        const {},
    uniformPdfCrop: (json['uniformPdfCrop'] as List<dynamic>?)
        ?.map((value) => (value as num).toDouble())
        .toList(growable: false),
  );
}
