/// A document failure whose message is safe to present directly to the reader.
class ReaderException implements Exception {
  final String message;

  const ReaderException(this.message);

  @override
  String toString() => message;
}

/// Unsupported encryption of EPUB resources, not ordinary font obfuscation.
class EncryptedEpubException extends ReaderException {
  final String resourcePath;
  final String algorithm;

  const EncryptedEpubException({
    required this.resourcePath,
    required this.algorithm,
  }) : super(
         'This book contains DRM-protected or encrypted content that this reader cannot open.',
       );
}
