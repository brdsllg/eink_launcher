import 'package:flutter/material.dart';

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
      appBar: AppBar(
        title: Text(loading ? 'Starting launcher' : 'Launcher recovery'),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loading
                      ? 'Loading settings and checking storage access…'
                      : message ?? 'The launcher needs help starting.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!loading)
                      OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('Retry startup'),
                      ),
                    if (!loading)
                      OutlinedButton(
                        onPressed: onUseRoot,
                        child: const Text('Use storage root'),
                      ),
                    OutlinedButton(
                      onPressed: onOpenApps,
                      child: const Text('Open app drawer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
