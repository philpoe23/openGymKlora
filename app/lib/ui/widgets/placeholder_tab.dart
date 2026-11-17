import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'common.dart';

/// A tab body that is not built yet: a header and "Coming next".
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KHeader(title, trailing: trailing),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: ShellInsets.bottomOf(context)),
            child: Center(
              child: Text('Coming next', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: surfacesOf(context).inkSoft)),
            ),
          ),
        ),
      ],
    ),
  );
}
