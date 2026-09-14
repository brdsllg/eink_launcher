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
  const DictionaryEntry(this.word, this.meanings);
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

/// Bundled WordNet data; no network access or first-run download. Only the
/// requested two-letter shards are decoded, off the UI isolate.
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

  Future<DictionaryShard> _shard(String word) async {
    final second = word.length > 1 && RegExp('[a-z]').hasMatch(word[1])
        ? word[1]
        : '_';
    final key = '${word[0]}$second';
    final cached = _shards.remove(key);
    if (cached != null) {
      _shards[key] = cached;
      return cached;
    }
    if (_shards.length >= 4) _shards.remove(_shards.keys.first);
    final pending = _loadAsset('assets/dictionary/$key.json.gz')
        .then((bytes) => compute(decodeDictionaryShard, bytes));
    _shards[key] = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_shards[key], pending)) _shards.remove(key);
      rethrow;
    }
  }

  Future<DictionaryEntry> lookup(String selection) async {
    final word = selection
        .trim()
        .replaceAll(RegExp('[\u00ad\u200b]'), '')
        .replaceAll('’', "'")
        .toLowerCase();
    if (word.isEmpty ||
        word.length > 100 ||
        !RegExp(r"^[a-z]+(?:['-][a-z]+)*$").hasMatch(word)) {
      throw const DictionaryException('Select a single English word.');
    }
    try {
      for (final candidate in _baseForms(word)) {
        final senses = (await _shard(candidate))[candidate];
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
