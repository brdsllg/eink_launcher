enum DocFormat {
  pdf,
  epub,
  txt,
  markdown;

  static DocFormat fromExtension(String extension) {
    final clean = extension.toLowerCase().replaceFirst('.', '');
    switch (clean) {
      case 'pdf':
        return DocFormat.pdf;
      case 'epub':
        return DocFormat.epub;
      case 'txt':
        return DocFormat.txt;
      case 'md':
      case 'markdown':
        return DocFormat.markdown;
      default:
        throw ArgumentError('Unsupported format: $extension');
    }
  }

  static DocFormat? tryFromExtension(String extension) {
    try {
      return fromExtension(extension);
    } catch (_) {
      return null;
    }
  }
}

class DocRef {
  final String id;
  final String path;
  final DocFormat format;
  final String title;
  final int fileSize;

  const DocRef({
    required this.id,
    required this.path,
    required this.format,
    required this.title,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'format': format.name,
    'title': title,
    'fileSize': fileSize,
  };

  factory DocRef.fromJson(Map<String, dynamic> json) => DocRef(
    id: json['id'] as String,
    path: json['path'] as String,
    format: DocFormat.values.byName(json['format'] as String),
    title: json['title'] as String,
    fileSize: json['fileSize'] as int,
  );
}
