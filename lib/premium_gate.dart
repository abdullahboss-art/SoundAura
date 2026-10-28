import 'package:flutter/material.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';
import 'package:soundclock/sc_theme.dart';

// -----------------------------------------------------------------------------
// Only two colors: Purple (SC.primary) and White (theme text color).
// Getters, so they update when the dark/light theme changes.
// -----------------------------------------------------------------------------
Color get _purple => SC.primary;
Color get _text => SC.text;
Color get _surface => SC.cardBg;
const Color _onPurple = Colors.white; // always white on top of purple


class PremiumGate {
  PremiumGate._();

  static bool ensure(
    BuildContext context, {
    required bool allowed,
    required PremiumReason reason,
  }) {
    if (allowed) return true;
    showPremiumSheet(context, reason: reason);
    return false;
  }

  static bool download(BuildContext context, int currentCount) => ensure(
        context,
        allowed: PremiumService.instance.canDownload(currentCount),
        reason: PremiumReason.downloads,
      );

  static bool playlist(BuildContext context, int currentCount) => ensure(
        context,
        allowed: PremiumService.instance.canCreatePlaylist(currentCount),
        reason: PremiumReason.playlists,
      );

  static bool feature(BuildContext context) => ensure(
        context,
        allowed: PremiumService.instance.isPremium,
        reason: PremiumReason.general,
      );
}



class UsageMeter extends StatelessWidget {
  const UsageMeter({
    super.key,
    required this.icon,
    required this.label,
    required this.used,
    required this.limit,
    this.reason = PremiumReason.general,
  });

  final IconData icon;
  final String label;
  final int used;
  final int limit;
  final PremiumReason reason;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PremiumService.instance,
      builder: (context, _) {
        if (PremiumService.instance.isPremium) return const SizedBox.shrink();

        final ratio = (used / limit).clamp(0.0, 1.0);
        final full = used >= limit;
        final near = ratio >= 0.7;
        final left = (limit - used).clamp(0, limit);

        final String hint = full
            ? 'You\u2019ve reached your limit. Go Premium for unlimited access.'
            : near
                ? 'Only $left left. Premium has no limits.'
                : 'Free plan: up to $limit.';

        // Border: normal < near < full (only the alpha of purple changes)
        final borderAlpha = full ? 220 : (near ? 160 : 100);

        return GestureDetector(
          onTap: () => showPremiumSheet(context, reason: reason),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _purple.withAlpha(borderAlpha)),
              boxShadow: [
                BoxShadow(color: _purple.withAlpha(40), blurRadius: 16),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: _purple, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${used > limit ? limit : used} / $limit',
                      style: TextStyle(
                        color: _purple,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: _purple.withAlpha(50),
                    valueColor: AlwaysStoppedAnimation<Color>(_purple),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hint,
                        style: TextStyle(color: _text, fontSize: 12),
                      ),
                    ),
                    if (full || near)
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _purple,
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: _onPurple,
                          size: 15,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Locks any widget behind Premium (free users see it slightly dimmed with a
/// purple lock badge, and tapping opens the premium sheet).
///
/// Example:
///   PremiumLock(
///     reason: PremiumReason.general,
///     child: SleepTimerTile(),
///   )
class PremiumLock extends StatelessWidget {
  const PremiumLock({
    super.key,
    required this.child,
    this.reason = PremiumReason.general,
  });

  final Widget child;
  final PremiumReason reason;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PremiumService.instance,
      builder: (context, _) {
        if (PremiumService.instance.isPremium) return child;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showPremiumSheet(context, reason: reason),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0.45, child: AbsorbPointer(child: child)),
              Positioned(
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _purple,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 13, color: _onPurple),
                      SizedBox(width: 4),
                      Text(
                        'PRO',
                        style: TextStyle(
                          color: _onPurple,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}