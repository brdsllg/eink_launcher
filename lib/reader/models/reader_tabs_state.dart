import 'doc_ref.dart';

/// Lightweight tab metadata. Restoring this never opens a document.
class ReaderTabsState {
  ReaderTabsState({
    List<DocRef> documents = const [],
    String? selectedTabId,
    List<String> recency = const [],
    List<DocRef> recentlyClosed = const [],
  }) : documents = List.unmodifiable(_uniqueDocuments(documents)),
       selectedTabId = documents.any((doc) => doc.id == selectedTabId)
           ? selectedTabId
           : null,
       recency = List.unmodifiable(
         recency.toSet().where((id) => documents.any((doc) => doc.id == id)),
       ),
       recentlyClosed = List.unmodifiable(
         _closedOnly(recentlyClosed, documents),
       );

  final List<DocRef> documents;
  final String? selectedTabId;

  /// Document IDs in least- to most-recently-read order.
  final List<String> recency;

  /// Recently closed tabs, most recently closed first. Never overlaps
  /// [documents].
  final List<DocRef> recentlyClosed;

  static Iterable<DocRef> _uniqueDocuments(List<DocRef> documents) {
    // Updating a moved document retains the position of its original tab.
    final byId = <String, DocRef>{};
    for (final doc in documents) {
      byId[doc.id] = doc;
    }
    return byId.values;
  }

  static Iterable<DocRef> _closedOnly(List<DocRef> closed, List<DocRef> open) {
    final openIds = {for (final doc in open) doc.id};
    final seen = <String>{};
    return closed.where((doc) => !openIds.contains(doc.id) && seen.add(doc.id));
  }

  /// A damaged closed-tab entry is dropped on its own; it must never cost the
  /// user their open tabs.
  static DocRef? _tryParseDoc(Object? value) {
    try {
      return DocRef.fromJson(value as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static List<DocRef> _parseClosed(Object? raw) => raw is List<dynamic>
      ? [for (final value in raw) ?_tryParseDoc(value)]
      : const [];

  Map<String, dynamic> toJson() => {
    'documents': documents.map((doc) => doc.toJson()).toList(),
    'selectedTabId': selectedTabId,
    'recency': recency,
    // Omitted when empty so a library with no closed tabs is saved exactly as
    // it was before this list existed.
    if (recentlyClosed.isNotEmpty)
      'recentlyClosed': recentlyClosed.map((doc) => doc.toJson()).toList(),
  };

  factory ReaderTabsState.fromJson(Map<String, dynamic> json) =>
      ReaderTabsState(
        documents: (json['documents'] as List<dynamic>? ?? const [])
            .map((doc) => DocRef.fromJson(doc as Map<String, dynamic>))
            .toList(),
        selectedTabId: json['selectedTabId'] as String?,
        recency: (json['recency'] as List<dynamic>? ?? const []).cast<String>(),
        recentlyClosed: _parseClosed(json['recentlyClosed']),
      );
}
