import 'package:flutter/material.dart';

import '../widgets/adaptive_grid.dart';

/// No reader, preferences, battery stream, or file listing is needed here.
class LauncherRecoveryScreen extends StatelessWidget {
  final bool loading;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onUseRoot;
  final VoidCallback onOpenApps;

  const LauncherRecoveryScreen({
    super.key,
    required this.loading,
    this.message,
    required this.onRetry,
    required this.onUseRoot,
    required this.onOpenApps,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: GridAppBar(
        automaticallyImplyLeading: false,
        title: Text(loading ? 'Starting launcher' : 'Launcher recovery'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loading
                        ? 'Loading settings and checking storage access…'
                        : message ?? 'The launcher needs help starting.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) => GridActions(
                      minCellWidth: 176,
                      maxColumns: constraints.maxWidth >= 528 ? 3 : 1,
                      children: [
                        if (!loading)
                          TextButton(
                            onPressed: onRetry,
                            child: const Text('Retry startup'),
                          ),
                        if (!loading)
                          TextButton(
                            onPressed: onUseRoot,
                            child: const Text('Use storage root'),
                          ),
                        TextButton(
                          onPressed: onOpenApps,
                          child: const Text('Open app drawer'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
