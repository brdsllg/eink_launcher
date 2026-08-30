import 'reading_position.dart';

class Bookmark {
  final String id;
  final String docId;
  final DateTime createdAt;
  final String label;
  final ReadingPosition position;

  const Bookmark({
    required this.id,
    required this.docId,
    required this.createdAt,
    required this.label,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'docId': docId,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'position': position.toJson(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    docId: json['docId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    label: json['label'] as String,
    position: ReadingPosition.fromJson(
      json['position'] as Map<String, dynamic>,
    ),
  );
}
