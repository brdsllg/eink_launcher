/// Resolves common filename extensions to precise MIME types before a file is
/// handed to Android. Avoiding `*/*` keeps unrelated apps out of the resolver.
class FileMimeTypeService {
  const FileMimeTypeService._();

  static const String fallbackType = 'application/octet-stream';

  static const Map<String, String> _types = {
    // Documents and ebooks.
    'pdf': 'application/pdf',
    'epub': 'application/epub+zip',
    'mobi': 'application/x-mobipocket-ebook',
    'azw': 'application/vnd.amazon.ebook',
    'azw3': 'application/vnd.amazon.ebook',
    'fb2': 'application/x-fictionbook+xml',
    'doc': 'application/msword',
    'dot': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'dotx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
    'odt': 'application/vnd.oasis.opendocument.text',
    'rtf': 'application/rtf',
    'xls': 'application/vnd.ms-excel',
    'xlt': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xlsm': 'application/vnd.ms-excel.sheet.macroEnabled.12',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pps': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'ppsx': 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
    'odp': 'application/vnd.oasis.opendocument.presentation',

    // Plain text, structured text, web, and source files.
    'txt': 'text/plain',
    'text': 'text/plain',
    'log': 'text/plain',
    'md': 'text/markdown',
    'markdown': 'text/markdown',
    'csv': 'text/csv',
    'tsv': 'text/tab-separated-values',
    'json': 'application/json',
    'jsonl': 'application/x-ndjson',
    'xml': 'application/xml',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'dart': 'text/plain',
    'py': 'text/x-python',
    'java': 'text/x-java-source',
    'kt': 'text/plain',
    'kts': 'text/plain',
    'c': 'text/x-c',
    'h': 'text/x-c',
    'cc': 'text/x-c++',
    'cpp': 'text/x-c++',
    'hpp': 'text/x-c++',
    'sh': 'application/x-sh',
    'ini': 'text/plain',
    'conf': 'text/plain',

    // Images.
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'jpe': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'avif': 'image/avif',
    'ico': 'image/x-icon',

    // Audio.
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'oga': 'audio/ogg',
    'opus': 'audio/opus',
    'wma': 'audio/x-ms-wma',
    'amr': 'audio/amr',
    'mid': 'audio/midi',
    'midi': 'audio/midi',
    'm3u': 'audio/x-mpegurl',
    'm3u8': 'application/vnd.apple.mpegurl',

    // Video.
    'mp4': 'video/mp4',
    'm4v': 'video/x-m4v',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    '3gp': 'video/3gpp',
    'mpeg': 'video/mpeg',
    'mpg': 'video/mpeg',

    // Archives, packages, and disk images.
    'zip': 'application/zip',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/vnd.rar',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'gzip': 'application/gzip',
    'tgz': 'application/gzip',
    'bz2': 'application/x-bzip2',
    'xz': 'application/x-xz',
    'apk': 'application/vnd.android.package-archive',
    'jar': 'application/java-archive',
    'iso': 'application/x-iso9660-image',
    'torrent': 'application/x-bittorrent',

    // Comics, fonts, contacts, calendars, and databases.
    'cbz': 'application/vnd.comicbook+zip',
    'cbr': 'application/vnd.comicbook-rar',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'vcf': 'text/vcard',
    'vcard': 'text/vcard',
    'ics': 'text/calendar',
    'sqlite': 'application/vnd.sqlite3',
    'sqlite3': 'application/vnd.sqlite3',
    'db': 'application/vnd.sqlite3',
  };

  static String forPath(String path) {
    final filename = path.substring(path.lastIndexOf('/') + 1);
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) return fallbackType;
    final extension = filename.substring(dot + 1).toLowerCase();
    return _types[extension] ?? fallbackType;
  }
}
