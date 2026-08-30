import 'reading_position.dart';

class TocEntry {
  final String title;
  final int level;
  final ReadingPosition? position;
  final String? targetHref;
  final List<TocEntry> children;

  const TocEntry({
    required this.title,
    this.level = 0,
    this.position,
    this.targetHref,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'level': level,
    if (position != null) 'position': position!.toJson(),
    if (targetHref != null) 'targetHref': targetHref,
    if (children.isNotEmpty)
      'children': children.map((c) => c.toJson()).toList(),
  };

  factory TocEntry.fromJson(Map<String, dynamic> json) => TocEntry(
    title: json['title'] as String,
    level: json['level'] as int? ?? 0,
    position: json['position'] != null
        ? ReadingPosition.fromJson(json['position'] as Map<String, dynamic>)
        : null,
    targetHref: json['targetHref'] as String?,
    children:
        (json['children'] as List<dynamic>?)
            ?.map((c) => TocEntry.fromJson(c as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
