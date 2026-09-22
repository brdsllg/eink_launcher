import 'dart:async';

import 'package:flutter/material.dart';

import '../services/book_store_service.dart';

/// Persistent across reader routes, including a failed flush when going Home.
class ReadingStateWarning extends StatelessWidget {
  final Widget child;
  final BookStoreService store;
  const ReadingStateWarning({
    super.key,
    required this.child,
    required this.store,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: store.saveError,
    builder: (context, message, _) => Column(
      children: [
        if (message != null)
          Material(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(store.flush()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}
