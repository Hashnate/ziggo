import 'package:flutter/material.dart';

import '../services/app_version_service.dart';

/// Displays the installed app version dynamically for each mobile release.
class AppVersionText extends StatefulWidget {
  final String prefix;
  final String suffix;
  final String? fallbackText;
  final TextStyle? style;

  const AppVersionText({
    super.key,
    this.prefix = '',
    this.suffix = '',
    this.fallbackText,
    this.style,
  });

  @override
  State<AppVersionText> createState() => _AppVersionTextState();
}

class _AppVersionTextState extends State<AppVersionText> {
  Future<String>? _versionFuture;

  @override
  void initState() {
    super.initState();
    final cached = AppVersionService.cachedVersion;
    if (cached == null || cached.isEmpty) {
      _versionFuture = AppVersionService.getVersion();
    }
  }

  Widget _buildText(String text) => Text(text, style: widget.style);

  @override
  Widget build(BuildContext context) {
    final cached = AppVersionService.cachedVersion;
    if (cached != null && cached.isNotEmpty) {
      return _buildText('${widget.prefix}$cached${widget.suffix}');
    }

    return FutureBuilder<String>(
      future: _versionFuture ??= AppVersionService.getVersion(),
      builder: (context, snapshot) {
        final version = snapshot.data ?? '';
        if (version.isNotEmpty) {
          return _buildText('${widget.prefix}$version${widget.suffix}');
        }
        if (widget.fallbackText != null) {
          return _buildText(widget.fallbackText!);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
