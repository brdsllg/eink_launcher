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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => unawaited(store.flush()),
                        child: const Text(
                          'Retry',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
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
