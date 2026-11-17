// A section label with an action at its end ("RECENT ··· See all").

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';

class KSectionHeader extends StatelessWidget {
  const KSectionHeader(this.text, {super.key, this.action, this.onAction, this.trailing, this.padding});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  /// Shown instead of the action (a quiet count, a tag).
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = surfacesOf(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 22, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(fontFamily: K.font, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: s.inkSoft),
            ),
          ),
          ?trailing,
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: s.accent,
                minimumSize: const Size(44, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: const TextStyle(fontFamily: K.font, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
