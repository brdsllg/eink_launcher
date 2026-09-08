import 'package:flutter/material.dart';

import '../../widgets/adaptive_grid.dart';

/// Static e-ink fallback with an explicit recovery action and an exit.
class ReaderErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ReaderErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GridActions(
                maxColumns: 2,
                children: [
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: Text(retryLabel)),
                  IconButton(
                    key: const Key('reader-error-home-button'),
                    tooltip: 'Home',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
