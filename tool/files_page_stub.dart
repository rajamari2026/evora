import 'package:flutter/material.dart';

/// Placeholder used only if the build had to drop the file_picker plugin.
List<Widget> filesSlivers(BuildContext context) => [
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'The Files page is not available in this build.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ];
