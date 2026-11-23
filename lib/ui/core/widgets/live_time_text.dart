import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../../domain/services/relative_time_formatter.dart';

/// Displays a live bilingual relative timestamp (e.g., `ឥឡូវនេះ` / `Just now`
/// → `១ នាទីមុន` / `1m ago`) that automatically ticks forward while mounted.
class LiveRelativeTimeText extends StatefulWidget {
  const LiveRelativeTimeText({
    super.key,
    required this.timestamp,
    required this.englishFirst,
    this.prefix = '',
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final DateTime timestamp;
  final bool englishFirst;
  final String prefix;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  State<LiveRelativeTimeText> createState() => _LiveRelativeTimeTextState();
}

class _LiveRelativeTimeTextState extends State<LiveRelativeTimeText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relative = RelativeTimeFormatter.formatRelative(
      widget.timestamp,
      englishFirst: widget.englishFirst,
    );
    return Text(
      '${widget.prefix}$relative',
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
  }
}

/// Rebuilds once per second while [report] is still within its 15-minute
/// citizen withdrawal/edit grace window, and stops ticking automatically once
/// the window expires or the widget disposes.
class LiveWithdrawalCountdown extends StatefulWidget {
  const LiveWithdrawalCountdown({
    super.key,
    required this.report,
    required this.builder,
  });

  final CivicReport report;
  final Widget Function(
    BuildContext context,
    bool canWithdraw,
    Duration remaining,
  )
  builder;

  @override
  State<LiveWithdrawalCountdown> createState() =>
      _LiveWithdrawalCountdownState();
}

class _LiveWithdrawalCountdownState extends State<LiveWithdrawalCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LiveWithdrawalCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id ||
        oldWidget.report.status != widget.report.status ||
        oldWidget.report.createdAt != widget.report.createdAt ||
        oldWidget.report.createdByCurrentUser !=
            widget.report.createdByCurrentUser) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.report.canWithdraw()) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!widget.report.canWithdraw()) {
        timer.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.report.remainingWithdrawalTime();
    return widget.builder(context, remaining > Duration.zero, remaining);
  }
}
