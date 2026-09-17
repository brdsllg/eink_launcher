import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DictionaryMeaning {
  final String partOfSpeech;
  final String definition;
  final String? example;
  const DictionaryMeaning(this.partOfSpeech, this.definition, this.example);
}

class DictionaryEntry {
  final String word;
  final List<DictionaryMeaning> meanings;
  final String source;
  final String sourceDetail;

  const DictionaryEntry(
    this.word,
    this.meanings, {
    this.source = 'WordNet 3.0',
    this.sourceDetail = 'English • Offline',
  });
}

class DictionaryException implements Exception {
  final String message;
  const DictionaryException(this.message);
}

typedef DictionaryShard = Map<String, List<List<String>>>;

DictionaryShard decodeDictionaryShard(Uint8List bytes) {
  final data =
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  return data.map(
    (word, senses) => MapEntry(
      word,
      (senses as List).map((sense) => (sense as List).cast<String>()).toList(),
    ),
  );
}

/// Bundled WordNet, Hebrew Wiktionary and Jastrow data. No network access or
/// first-run download is needed. Only the requested shard is decoded, off the
/// UI isolate.
class DictionaryService {
  static final instance = DictionaryService();
  final Future<Uint8List> Function(String path) _loadAsset;
  final _shards = <String, Future<DictionaryShard>>{};

  DictionaryService({Future<Uint8List> Function(String path)? loadAsset})
    : _loadAsset = loadAsset ?? _loadBundledAsset;

  static Future<Uint8List> _loadBundledAsset(String path) async {
    final bytes = await rootBundle.load(path);
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  Future<DictionaryShard> _englishShard(String word) {
    final second = word.length > 1 && RegExp('[a-z]').hasMatch(word[1])
        ? word[1]
        : '_';
    final key = '${word[0]}$second';
    return _shard('english:$key', 'assets/dictionary/$key.json.gz');
  }

  Future<DictionaryShard> _hebrewShard(String collection, String word) {
    final key = word.runes.first.toRadixString(16).padLeft(4, '0');
    return _shard(
      '$collection:$key',
      'assets/dictionary/$collection/$key.json.gz',
    );
  }

  Future<DictionaryShard> _shard(String key, String path) async {
    final cached = _shards.remove(key);
    if (cached != null) {
      _shards[key] = cached;
      return cached;
    }
    if (_shards.length >= 4) _shards.remove(_shards.keys.first);
    final pending = _loadAsset(path)
        .then((bytes) => compute(decodeDictionaryShard, bytes));
    _shards[key] = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_shards[key], pending)) _shards.remove(key);
      rethrow;
    }
  }

  Future<DictionaryEntry> lookup(String selection) async =>
      (await lookupAll(selection)).first;

  Future<List<DictionaryEntry>> lookupAll(String selection) async {
    final cleaned = selection
        .trim()
        .replaceAll(RegExp('[\u00ad\u200b]'), '')
        .replaceAll('’', "'");
    if (cleaned.isEmpty || cleaned.length > 100) {
      throw const DictionaryException(
        'Select a single English, Hebrew, or Aramaic word.',
      );
    }

    final english = cleaned.toLowerCase();
    if (RegExp(r"^[a-z]+(?:['-][a-z]+)*$").hasMatch(english)) {
      return [await _lookupEnglish(english)];
    }

    final hebrew = _normalizeHebrew(cleaned);
    if (hebrew.isEmpty ||
        RegExp(r'\s').hasMatch(cleaned) ||
        RegExp(r'[a-zA-Z0-9]').hasMatch(cleaned)) {
      throw const DictionaryException(
        'Select a single English, Hebrew, or Aramaic word.',
      );
    }

    try {
      final results = <DictionaryEntry>[];
      final modern = await _lookupHebrewCollection(
        hebrew,
        collection: 'hebrew-modern',
        source: 'Hebrew Wiktionary',
        sourceDetail: 'Modern Hebrew • Kaikki • Offline',
      );
      if (modern != null) results.add(modern);
      final jastrow = await _lookupHebrewCollection(
        hebrew,
        collection: 'jastrow',
        source: 'Jastrow Dictionary',
        sourceDetail: 'Rabbinic Hebrew & Aramaic • 1903 • Offline',
      );
      if (jastrow != null) results.add(jastrow);
      if (results.isNotEmpty) return List.unmodifiable(results);
    } catch (_) {
      throw const DictionaryException(
        'Could not load the offline Hebrew dictionaries. Try again.',
      );
    }
    throw DictionaryException(
      'No Hebrew or Aramaic definition found for “$hebrew” in the offline dictionaries.',
    );
  }

  Future<DictionaryEntry> _lookupEnglish(String word) async {
    try {
      for (final candidate in _baseForms(word)) {
        final senses = (await _englishShard(candidate))[candidate];
        if (senses == null || senses.isEmpty) continue;
        return DictionaryEntry(
          candidate,
          List.unmodifiable(
            senses.map((sense) {
              final gloss = sense[1];
              final exampleStart = gloss.indexOf('; "');
              return DictionaryMeaning(
                sense[0],
                exampleStart < 0 ? gloss : gloss.substring(0, exampleStart),
                exampleStart < 0 ? null : gloss.substring(exampleStart + 2),
              );
            }),
          ),
        );
      }
    } catch (_) {
      throw const DictionaryException(
        'Could not load the offline dictionary. Try again.',
      );
    }
    throw DictionaryException(
      'No English definition found for “$word” in the offline dictionary.',
    );
  }

  Future<DictionaryEntry?> _lookupHebrewCollection(
    String word, {
    required String collection,
    required String source,
    required String sourceDetail,
  }) async {
    final senses = (await _hebrewShard(collection, word))[word];
    if (senses == null || senses.isEmpty) return null;
    final displayWord = senses.first.length > 3 && senses.first[3].isNotEmpty
        ? senses.first[3]
        : word;
    return DictionaryEntry(
      displayWord,
      List.unmodifiable(
        senses.map(
          (sense) => DictionaryMeaning(
            sense[0],
            sense[1],
            sense.length > 2 && sense[2].isNotEmpty ? sense[2] : null,
          ),
        ),
      ),
      source: source,
      sourceDetail: sourceDetail,
    );
  }

  String _normalizeHebrew(String value) => value
      .replaceAll(RegExp(r'[\u0591-\u05c7]'), '')
      .replaceAll(RegExp(r'[^\u05d0-\u05ea]'), '');

  Iterable<String> _baseForms(String word) sync* {
    yield word;
    if (word.endsWith("'s") && word.length > 2) {
      yield word.substring(0, word.length - 2);
    }
    final seen = <String>{word};
    for (final (suffix, replacement) in [
      ('ies', 'y'),
      ('men', 'man'),
      ('ches', 'ch'),
      ('shes', 'sh'),
      ('xes', 'x'),
      ('zes', 'z'),
      ('ses', 's'),
      ('s', ''),
      ('ied', 'y'),
      ('ing', ''),
      ('ing', 'e'),
      ('ed', ''),
      ('ed', 'e'),
      ('er', ''),
      ('er', 'e'),
      ('est', ''),
      ('est', 'e'),
    ]) {
      if (!word.endsWith(suffix) || word.length <= suffix.length + 1) continue;
      final base = word.substring(0, word.length - suffix.length) + replacement;
      if (seen.add(base)) yield base;
      if (replacement.isEmpty &&
          ['ing', 'ed', 'er', 'est'].contains(suffix) &&
          base.length > 2 &&
          base[base.length - 1] == base[base.length - 2]) {
        final undoubled = base.substring(0, base.length - 1);
        if (seen.add(undoubled)) yield undoubled;
      }
    }
  }
}
