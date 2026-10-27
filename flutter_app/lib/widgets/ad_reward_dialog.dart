import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';
import 'game_chrome.dart' show gameButton;

/// Only a successful fresh count enables watching; failed queries can be retried.
class AdRewardDialog extends StatefulWidget {
  const AdRewardDialog({
    super.key,
    required this.loadUsed,
    required this.adReady,
    required this.isAdLoading,
    required this.maxRewards,
    required this.onWatch,
  });

  final Future<int?> Function() loadUsed;
  final ValueListenable<bool> adReady;
  final bool Function() isAdLoading;
  final int maxRewards;
  final VoidCallback onWatch;

  @override
  State<AdRewardDialog> createState() => _AdRewardDialogState();
}

class _AdRewardDialogState extends State<AdRewardDialog> {
  int? _used;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _used = null;
    });
    int? used;
    try {
      used = await widget.loadUsed();
    } catch (_) {
      // A failed request never authorizes an ad using an old count.
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _used = used != null && used >= 0 && used <= widget.maxRewards
          ? used
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final used = _used;
    final canWatch = used != null && used < widget.maxRewards;
    return AlertDialog(
      backgroundColor: Cartoon.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: Cartoon.ink, width: 2.5),
      ),
      title: Row(
        children: [
          Icon(
            Icons.play_circle_rounded,
            size: 30,
            color: Cartoon.onSurface(const Color(0xFF7E57C2)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              used != null && !canWatch
                  ? l10n.shopAdRewardDone
                  : l10n.shopAdWatchTitle,
              style: Cartoon.text(size: 20),
            ),
          ),
        ],
      ),
      content: Text(
        _loading
            ? l10n.gameCheckingState
            : used == null
            ? l10n.loginServerNoResponse
            : canWatch
            ? l10n.shopAdWatchProgress(used, widget.maxRewards)
            : l10n.shopAdRewardDoneSubtitle,
        style: Cartoon.userText(size: 15, weight: FontWeight.w600),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Cartoon.ink),
          child: Text(l10n.commonClose, style: Cartoon.text(size: 17)),
        ),
        if (!_loading && used == null)
          TextButton(onPressed: _load, child: Text(l10n.noticeRetry)),
        if (canWatch)
          ValueListenableBuilder<bool>(
            valueListenable: widget.adReady,
            builder: (context, ready, _) {
              final ok = ready && !widget.isAdLoading();
              return gameButton(
                ok
                    ? l10n.shopAdWatchForGold(used, widget.maxRewards)
                    : l10n.shopAdPreparing,
                ok
                    ? () {
                        Navigator.pop(context);
                        widget.onWatch();
                      }
                    : null,
                color: Cartoon.onSurface(const Color(0xFF7E57C2)),
                size: 16,
                hPad: 14,
              );
            },
          ),
      ],
    );
  }
}
