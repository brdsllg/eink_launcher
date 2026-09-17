import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/adaptive_grid.dart';
import '../services/dictionary_service.dart';

Future<void> showDictionaryDefinition(BuildContext context, String word) =>
    showDialog<void>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => DictionaryDialog(word: word),
    );

class DictionaryDialog extends StatefulWidget {
  final String word;
  final Future<DictionaryEntry> Function(String)? lookup;

  const DictionaryDialog({super.key, required this.word, this.lookup});

  @override
  State<DictionaryDialog> createState() => _DictionaryDialogState();
}

class _DictionaryDialogState extends State<DictionaryDialog> {
  late Future<List<DictionaryEntry>> _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final customLookup = widget.lookup;
    _result = customLookup == null
        ? DictionaryService.instance.lookupAll(widget.word)
        : customLookup(widget.word).then((entry) => [entry]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<DictionaryEntry>>(
    future: _result,
    builder: (context, snapshot) {
      final entries = snapshot.data;
      return GridDialog(
        title: Text(widget.word),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (snapshot.connectionState != ConnectionState.done)
              const Text('Looking up definition…')
            else if (snapshot.hasError)
              Text(
                snapshot.error is DictionaryException
                    ? (snapshot.error! as DictionaryException).message
                    : 'Could not load the definition. Try again.',
              )
            else if (entries != null)
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0) const Divider(height: 32),
                Text(
                  entries[index].source,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  entries[index].sourceDetail,
                  style: const TextStyle(fontSize: 12),
                ),
                if (entries[index].word.toLowerCase() !=
                    widget.word.toLowerCase())
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entries[index].word,
                      textDirection:
                          RegExp(r'[\u05d0-\u05ea]')
                              .hasMatch(entries[index].word)
                          ? TextDirection.rtl
                          : null,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                for (final meaning in entries[index].meanings)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (meaning.partOfSpeech.isNotEmpty)
                          Text(
                            meaning.partOfSpeech,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        Text(meaning.definition),
                        if (meaning.example?.isNotEmpty == true)
                          Text(
                            meaning.example!,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
              ],
            const SizedBox(height: 16),
            const Text(
              'English, modern Hebrew, rabbinic Hebrew & Aramaic • Offline',
              style: TextStyle(fontSize: 12),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (context) => GridDialog(
                  title: const Text('Dictionary sources & licenses'),
                  content: FutureBuilder<String>(
                    future: Future.wait([
                      rootBundle.loadString(
                        'assets/dictionary/SOURCES_AND_LICENSES.txt',
                      ),
                      rootBundle.loadString('assets/dictionary/LICENSE.txt'),
                    ]).then((parts) => '${parts[0]}\n\n${parts[1]}'),
                    builder: (_, snapshot) => Text(
                      snapshot.data ??
                          (snapshot.hasError
                              ? 'Could not load license.'
                              : 'Loading…'),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Dictionary sources & licenses'),
            ),
          ],
        ),
        actions: [
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(_load),
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
