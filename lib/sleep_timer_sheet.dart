import 'package:flutter/material.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';

const Color _surface = Color(0xFF0F1A33);
const Color _cyan = Color(0xFF22C7E8);
const Color _orange = Color(0xFFFF9A3D);
const Color _gold = Color(0xFFFFC043);

/// Player screen ke sleep/timer button par: showSleepTimerSheet(context);
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      const options = <(String, Duration)>[
        ('15 minutes', Duration(minutes: 15)),
        ('30 minutes', Duration(minutes: 30)),
        ('45 minutes', Duration(minutes: 45)),
        ('1 hour', Duration(hours: 1)),
      ];
      final isPro = PremiumService.instance.isPremium;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Sleep Timer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!isPro)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Ye Premium feature hai. Koi bhi option dabayein to plans khulenge.',
                  style: TextStyle(color: _gold, fontSize: 12),
                ),
              ),
            ValueListenableBuilder<Duration?>(
              valueListenable: PlayerService.instance.sleepRemaining,
              builder: (_, left, __) {
                if (left == null || !isPro) return const SizedBox.shrink();
                final m = left.inMinutes.toString().padLeft(2, '0');
                final s = (left.inSeconds % 60).toString().padLeft(2, '0');
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Music $m:$s baad ruk jayega',
                    style: const TextStyle(color: _cyan, fontSize: 13),
                  ),
                );
              },
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$1, style: const TextStyle(color: Colors.white)),
                trailing: isPro
                    ? null
                    : const Icon(Icons.lock_rounded, color: _gold, size: 20),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (!isPro) {
                    showPremiumSheet(context);
                    return;
                  }
                  PlayerService.instance.startSleepTimer(o.$2);
                },
              ),
            ValueListenableBuilder<Duration?>(
              valueListenable: PlayerService.instance.sleepRemaining,
              builder: (_, left, __) {
                if (left == null || !isPro) return const SizedBox.shrink();
                return ListTile(
                  leading:
                      const Icon(Icons.timer_off_rounded, color: _orange),
                  title: const Text('Timer band karein',
                      style: TextStyle(color: _orange)),
                  onTap: () {
                    PlayerService.instance.cancelSleepTimer();
                    Navigator.of(ctx).pop();
                  },
                );
              },
            ),
          ],
        ),
      );
    },
  );
}