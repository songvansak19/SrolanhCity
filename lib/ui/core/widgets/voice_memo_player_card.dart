import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/services/audio_player_service.dart';
import '../l10n.dart';
import '../theme.dart';

/// Reusable, WCAG 2.1 AA accessible playable Voice Memo card used across
/// Report Wizard Step 2, ReportSubmittedPage, TrackingPage (top + comments),
/// MapPage incident bottom sheet, and StaffConsolePage.
class VoiceMemoPlayerCard extends StatefulWidget {
  const VoiceMemoPlayerCard({
    super.key,
    required this.audioPath,
    required this.bilingual,
    this.durationSeconds,
    this.subtitle,
    this.compact = false,
    this.surfaceColor,
    this.playButtonKey,
    this.deleteButtonKey,
    this.onDelete,
    this.audioPlayerService,
  });

  final String audioPath;
  final Bilingual bilingual;
  final int? durationSeconds;
  final String? subtitle;
  final bool compact;
  final Color? surfaceColor;
  final Key? playButtonKey;
  final Key? deleteButtonKey;
  final VoidCallback? onDelete;
  final AudioPlayerService? audioPlayerService;

  static String formatDuration(int? seconds) {
    final safe = (seconds == null || seconds < 1) ? 1 : seconds;
    final mins = safe ~/ 60;
    final rem = safe % 60;
    return '$mins:${rem.toString().padLeft(2, '0')}';
  }

  @override
  State<VoiceMemoPlayerCard> createState() => _VoiceMemoPlayerCardState();
}

class _VoiceMemoPlayerCardState extends State<VoiceMemoPlayerCard> {
  late final AudioPlayerService _player;
  late final bool _ownsPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _ownsPlayer = widget.audioPlayerService == null;
    _player = widget.audioPlayerService ?? AudioPlayerService.createDefault();
  }

  @override
  void didUpdateWidget(covariant VoiceMemoPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath && _isPlaying) {
      unawaited(_player.stop());
      _isPlaying = false;
    }
  }

  @override
  void dispose() {
    if (_ownsPlayer) {
      unawaited(_player.dispose());
    } else {
      unawaited(_player.stop());
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    final started = await _player.play(
      widget.audioPath,
      onCompleted: () {
        if (mounted) setState(() => _isPlaying = false);
      },
    );
    if (!mounted) return;
    if (started) {
      setState(() => _isPlaying = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.bilingual.primary(
              'កំណត់ត្រាសំឡេងត្រូវបានរក្សាទុកក្នុងរបាយការណ៍នេះរួចរាល់',
              'Voice memo is saved and attached to this report.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.bilingual;
    final durationText = VoiceMemoPlayerCard.formatDuration(
      widget.durationSeconds,
    );
    final titleText = _isPlaying
        ? tr.primary(
            'កំពុងចាក់ស្តាប់សំឡេង ($durationText)...',
            'Playing voice memo ($durationText)...',
          )
        : tr.primary(
            'កំណត់ត្រាសំឡេង ($durationText)',
            'Voice Memo ($durationText)',
          );
    final bgColor =
        widget.surfaceColor ??
        (widget.compact ? Colors.white : AppColors.tealSoft);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 12,
        vertical: widget.compact ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.compact ? 13 : 16),
        border: Border.all(
          color: AppColors.teal.withValues(alpha: widget.compact ? 0.30 : 0.28),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            excludeSemantics: true,
            label: _isPlaying
                ? tr.primary('ផ្អាកកំណត់ត្រាសំឡេង', 'Stop voice memo')
                : tr.primary('ចាក់ស្តាប់កំណត់ត្រាសំឡេង', 'Play voice memo'),
            child: InkWell(
              key: widget.playButtonKey,
              onTap: _togglePlay,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: CircleAvatar(
                    radius: widget.compact ? 16 : 19,
                    backgroundColor: _isPlaying
                        ? AppColors.danger
                        : AppColors.teal,
                    child: Icon(
                      _isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: widget.compact ? 18 : 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.mic_rounded,
                      size: 13,
                      color: AppColors.tealDark,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.compact ? 12 : 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.tealDark,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.subtitle != null &&
                    widget.subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.onDelete != null)
            IconButton(
              key: widget.deleteButtonKey,
              tooltip: tr.primary('លុបកំណត់ត្រាសំឡេង', 'Remove voice memo'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.muted,
              ),
              onPressed: () {
                unawaited(_player.stop());
                if (_isPlaying && mounted) {
                  setState(() => _isPlaying = false);
                }
                widget.onDelete?.call();
              },
            ),
        ],
      ),
    );
  }
}
