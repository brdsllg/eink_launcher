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
  late Future<DictionaryEntry> _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _result = (widget.lookup ?? DictionaryService.instance.lookup)(widget.word);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DictionaryEntry>(
    future: _result,
    builder: (context, snapshot) {
      final entry = snapshot.data;
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
            else if (entry != null) ...[
              if (entry.word.toLowerCase() != widget.word.toLowerCase())
                Text(
                  entry.word,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              for (final meaning in entry.meanings)
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
              'English • WordNet 3.0 • Offline',
              style: TextStyle(fontSize: 12),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                animationStyle: AnimationStyle.noAnimation,
                builder: (context) => GridDialog(
                  title: const Text('Dictionary license'),
                  content: FutureBuilder<String>(
                    future: rootBundle.loadString(
                      'assets/dictionary/LICENSE.txt',
                    ),
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
              child: const Text('Dictionary license'),
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
