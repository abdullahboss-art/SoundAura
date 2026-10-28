import 'package:flutter/material.dart';
import 'package:soundclock/player_ui.dart';

/// "No Internet Connection" screen.
class NoInternetPage extends StatelessWidget {
  final VoidCallback onRetry;

  /// Offline hone par downloaded gaane sunne ka shortcut (optional).
  final VoidCallback? onOpenDownloads;

  const NoInternetPage({
    super.key,
    required this.onRetry,
    this.onOpenDownloads,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MelodyColors.background,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MelodyColors.surface,
                border: Border.all(color: MelodyColors.cyan, width: 2),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white,
                size: 52,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Please check your network connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: 220,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [MelodyColors.orange, MelodyColors.pink],
                  ),
                ),
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (onOpenDownloads != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onOpenDownloads,
                icon: const Icon(Icons.download_done_rounded,
                    color: MelodyColors.cyan),
                label: const Text(
                  'Downloaded songs sunein',
                  style: TextStyle(color: MelodyColors.cyan),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
