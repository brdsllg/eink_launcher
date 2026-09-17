import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' show parseFragment;

const _hebrewLetters = 'אבגדהוזחטיךכלםמןנסעףפץצקרשת';

/// Builds the bundled Hebrew dictionary shards from:
///
/// * https://kaikki.org/dictionary/Hebrew/kaikki.org-dictionary-Hebrew.jsonl
/// * https://jastrow.app/data/jastrow-part1.jsonl
/// * https://jastrow.app/data/jastrow-part2.jsonl
///
/// Pass those three downloaded files in that order, or use the default names
/// shown in [main]. Source downloads are intentionally not committed.
Future<void> main(List<String> arguments) async {
  final kaikkiPath = arguments.isNotEmpty
      ? arguments[0]
      : 'kaikki-hebrew.jsonl';
  final jastrowPaths = arguments.length > 2
      ? arguments.sublist(1, 3)
      : ['jastrow-part1.jsonl', 'jastrow-part2.jsonl'];

  final modern = await _readKaikki(File(kaikkiPath));
  final jastrow = <String, List<List<String>>>{};
  for (final path in jastrowPaths) {
    await _readJastrow(File(path), jastrow);
  }

  final modernStats = await _writeShards(
    Directory('assets/dictionary/hebrew-modern'),
    modern,
  );
  final jastrowStats = await _writeShards(
    Directory('assets/dictionary/jastrow'),
    jastrow,
  );

  stdout.writeln(
    'Modern Hebrew: ${modern.length} lookup forms, '
    '${modernStats.entries} entries, ${modernStats.bytes} compressed bytes.',
  );
  stdout.writeln(
    'Jastrow: ${jastrow.length} lookup forms, '
    '${jastrowStats.entries} entries, ${jastrowStats.bytes} compressed bytes.',
  );
}

Future<Map<String, List<List<String>>>> _readKaikki(File source) async {
  final output = <String, List<List<String>>>{};
  await for (final line
      in source
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (!line.contains('Modern-Israeli') &&
        !line.contains('Modern Hebrew') &&
        !line.contains('Modern Israeli Hebrew')) {
      continue;
    }
    final record = jsonDecode(line) as Map<String, dynamic>;
    final word = record['word'] as String? ?? '';
    final displayWord = _canonicalForm(record) ?? word;
    final senses = <List<String>>[];
    for (final rawSense in (record['senses'] as List? ?? const [])) {
      final sense = rawSense as Map<String, dynamic>;
      final glosses = (sense['glosses'] as List? ?? const [])
          .whereType<String>();
      final example = _kaikkiExample(sense);
      for (final gloss in glosses) {
        final cleaned = _cleanText(gloss);
        if (cleaned.isNotEmpty) {
          senses.add([
            record['pos'] as String? ?? '',
            cleaned,
            example,
            displayWord,
          ]);
        }
      }
    }
    if (senses.isEmpty) continue;

    final aliases = <String>{word, displayWord};
    for (final rawForm in (record['forms'] as List? ?? const [])) {
      final form = rawForm as Map<String, dynamic>;
      final value = form['form'];
      if (value is! String || !_containsHebrew(value)) continue;
      final tags = (form['tags'] as List? ?? const []).whereType<String>();
      if (tags.any(
        const {
          'class',
          'inflection-template',
          'romanization',
          'table-tags',
        }.contains,
      )) {
        continue;
      }
      aliases.add(value);
    }
    for (final alias in aliases) {
      _addSenses(output, _normalizeHebrew(alias), senses);
    }
  }
  return output;
}

Future<void> _readJastrow(
  File source,
  Map<String, List<List<String>>> output,
) async {
  await for (final line
      in source
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final record = jsonDecode(line) as Map<String, dynamic>;
    final headword = record['hw'] as String? ?? '';
    final content = record['c'] as Map<String, dynamic>? ?? const {};
    final definitions = <String>[];
    _collectJastrowDefinitions(content['s'], definitions);
    if (definitions.isEmpty) continue;
    final morphology = content['mo'] as String? ?? '';
    final senses = definitions
        .map((definition) => [morphology, definition, '', headword])
        .toList(growable: false);
    final aliases = <String>{headword};
    for (final field in ['ah', 'pf']) {
      final value = record[field];
      if (value is List) aliases.addAll(value.whereType<String>());
    }
    for (final alias in aliases) {
      _addSenses(output, _normalizeHebrew(alias), senses);
    }
  }
}

void _collectJastrowDefinitions(Object? value, List<String> output) {
  if (value is List) {
    for (final item in value) {
      _collectJastrowDefinitions(item, output);
    }
    return;
  }
  if (value is! Map<String, dynamic>) return;
  final definition = value['d'];
  if (definition is String) {
    final number = value['n'] as String? ?? '';
    final text = _cleanHtml('$number $definition');
    if (text.isNotEmpty) output.add(text);
  }
  _collectJastrowDefinitions(value['s'], output);
}

String? _canonicalForm(Map<String, dynamic> record) {
  for (final rawForm in (record['forms'] as List? ?? const [])) {
    final form = rawForm as Map<String, dynamic>;
    final tags = (form['tags'] as List? ?? const []).whereType<String>();
    if (tags.contains('canonical') && form['form'] is String) {
      return form['form'] as String;
    }
  }
  return null;
}

String _kaikkiExample(Map<String, dynamic> sense) {
  for (final rawExample in (sense['examples'] as List? ?? const [])) {
    final example = rawExample as Map<String, dynamic>;
    final english = example['english'] ?? example['translation'];
    if (english is String && english.trim().isNotEmpty) {
      return _cleanText(english);
    }
  }
  return '';
}

void _addSenses(
  Map<String, List<List<String>>> output,
  String key,
  Iterable<List<String>> senses,
) {
  if (key.isEmpty) return;
  final target = output.putIfAbsent(key, () => []);
  for (final sense in senses) {
    if (!target.any(
      (existing) =>
          existing[0] == sense[0] &&
          existing[1] == sense[1] &&
          existing[3] == sense[3],
    )) {
      target.add(sense);
    }
  }
}

Future<({int entries, int bytes})> _writeShards(
  Directory directory,
  Map<String, List<List<String>>> entries,
) async {
  await directory.create(recursive: true);
  var compressedBytes = 0;
  var entryCount = 0;
  for (final letter in _hebrewLetters.runes.toSet()) {
    final shard = <String, List<List<String>>>{};
    for (final entry in entries.entries) {
      if (entry.key.runes.first == letter) shard[entry.key] = entry.value;
    }
    final sorted = Map.fromEntries(
      shard.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final List<int> bytes = GZipCodec(level: 9)
        .encode(utf8.encode(jsonEncode(sorted)));
    final filename = letter.toRadixString(16).padLeft(4, '0');
    await File('${directory.path}/$filename.json.gz').writeAsBytes(bytes);
    compressedBytes += bytes.length;
    entryCount += shard.length;
  }
  return (entries: entryCount, bytes: compressedBytes);
}

bool _containsHebrew(String value) =>
    RegExp(r'[\u05d0-\u05ea]').hasMatch(value);

String _normalizeHebrew(String value) {
  final withoutMarks = value
      .replaceAll(RegExp(r'[\u0591-\u05c7]'), '')
      .replaceAll(RegExp(r'[\u00ad\u200b]'), '');
  if (RegExp(r'[\u05d0-\u05ea]\s+[\u05d0-\u05ea]').hasMatch(withoutMarks)) {
    return '';
  }
  return withoutMarks.replaceAll(RegExp(r'[^\u05d0-\u05ea]'), '');
}

String _cleanHtml(String value) => _cleanText(parseFragment(value).text ?? '');

String _cleanText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
