sealed class ReadingPosition {
  const ReadingPosition();

  Map<String, dynamic> toJson();

  factory ReadingPosition.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'pdf') {
      return PdfReadingPosition.fromJson(json);
    } else if (type == 'text') {
      return TextReadingPosition.fromJson(json);
    }
    throw ArgumentError('Unknown reading position type: $type');
  }
}

class PdfReadingPosition extends ReadingPosition {
  final int pageIndex; // 0-based
  final double withinPage; // 0.0 to 1.0 vertical fraction

  const PdfReadingPosition({required this.pageIndex, this.withinPage = 0.0})
    : assert(withinPage >= 0.0 && withinPage <= 1.0);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'pdf',
    'pageIndex': pageIndex,
    'withinPage': withinPage,
  };

  factory PdfReadingPosition.fromJson(Map<String, dynamic> json) =>
      PdfReadingPosition(
        pageIndex: json['pageIndex'] as int,
        withinPage: (json['withinPage'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfReadingPosition &&
          runtimeType == other.runtimeType &&
          pageIndex == other.pageIndex &&
          (withinPage - other.withinPage).abs() < 0.0001;

  @override
  int get hashCode => pageIndex.hashCode ^ withinPage.hashCode;
}

class TextReadingPosition extends ReadingPosition {
  final int spineIndex;
  final int blockIndex;
  final int charOffset;

  const TextReadingPosition({
    required this.spineIndex,
    required this.blockIndex,
    required this.charOffset,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'spineIndex': spineIndex,
    'blockIndex': blockIndex,
    'charOffset': charOffset,
  };

  factory TextReadingPosition.fromJson(Map<String, dynamic> json) =>
      TextReadingPosition(
        spineIndex: json['spineIndex'] as int,
        blockIndex: json['blockIndex'] as int,
        charOffset: json['charOffset'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextReadingPosition &&
          runtimeType == other.runtimeType &&
          spineIndex == other.spineIndex &&
          blockIndex == other.blockIndex &&
          charOffset == other.charOffset;

  @override
  int get hashCode =>
      spineIndex.hashCode ^ blockIndex.hashCode ^ charOffset.hashCode;
}
