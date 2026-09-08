import 'doc_ref.dart';

/// Lightweight tab metadata. Restoring this never opens a document.
class ReaderTabsState {
  ReaderTabsState({
    List<DocRef> documents = const [],
    String? selectedTabId,
    List<String> recency = const [],
  }) : documents = List.unmodifiable(_uniqueDocuments(documents)),
       selectedTabId = documents.any((doc) => doc.id == selectedTabId)
           ? selectedTabId
           : null,
       recency = List.unmodifiable(
         recency.toSet().where((id) => documents.any((doc) => doc.id == id)),
       );

  final List<DocRef> documents;
  final String? selectedTabId;

  /// Document IDs in least- to most-recently-read order.
  final List<String> recency;

  static Iterable<DocRef> _uniqueDocuments(List<DocRef> documents) {
    // Updating a moved document retains the position of its original tab.
    final byId = <String, DocRef>{};
    for (final doc in documents) {
      byId[doc.id] = doc;
    }
    return byId.values;
  }

  Map<String, dynamic> toJson() => {
    'documents': documents.map((doc) => doc.toJson()).toList(),
    'selectedTabId': selectedTabId,
    'recency': recency,
  };

  factory ReaderTabsState.fromJson(Map<String, dynamic> json) =>
      ReaderTabsState(
        documents: (json['documents'] as List<dynamic>? ?? const [])
            .map((doc) => DocRef.fromJson(doc as Map<String, dynamic>))
            .toList(),
        selectedTabId: json['selectedTabId'] as String?,
        recency: (json['recency'] as List<dynamic>? ?? const []).cast<String>(),
      );
}
