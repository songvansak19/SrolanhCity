import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/report_repository.dart';
import '../l10n.dart';
import '../report_scope.dart';
import '../theme.dart';
import 'assistant_chat_panel.dart';
import 'assistant_scope.dart';

/// App-wide draggable, edge-snapping floating AI Civic Assistant bubble.
///
/// Mounted inside `MaterialApp.builder` so it floats seamlessly over Home, Map,
/// Alerts, Profile, Tracking, Area News, and My Reports while automatically
/// hiding during onboarding, Report Wizard, Lightbox, Help Center, dialogs,
/// bottom sheets, or when the on-screen keyboard is open.
class AssistantBubbleHost extends StatefulWidget {
  const AssistantBubbleHost({super.key});

  static const double bubbleSize = 56.0;
  static const double _edgeMargin = 14.0;
  static const double _wideBreakpoint = 600.0;
  static const double _railClearance = 84.0;

  @override
  State<AssistantBubbleHost> createState() => _AssistantBubbleHostState();
}

class _AssistantBubbleHostState extends State<AssistantBubbleHost> {
  bool _isDragging = false;
  Offset? _dragPosition;
  bool _showFirstRunHint = false;
  Timer? _hintTimer;
  bool _hintScheduledThisSession = false;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _maybeTriggerFirstRunHint(
    ReportRepository repo,
    bool visible,
    bool reduceMotion,
  ) {
    if (!visible ||
        reduceMotion ||
        _hintScheduledThisSession ||
        repo.settings.assistantHintSeen) {
      return;
    }
    _hintScheduledThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showFirstRunHint = true);
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        setState(() => _showFirstRunHint = false);
        _markHintSeen(repo);
      });
    });
  }

  void _dismissFirstRunHint(ReportRepository repo) {
    _hintTimer?.cancel();
    if (_showFirstRunHint) {
      setState(() => _showFirstRunHint = false);
    }
    _markHintSeen(repo);
  }

  void _markHintSeen(ReportRepository repo) {
    if (repo.settings.assistantHintSeen) return;
    repo.updateSettings(repo.settings.copyWith(assistantHintSeen: true));
  }

  void _hideBubbleWithUndo(BuildContext context, Bilingual tr) {
    final repo = ReportScope.read(context);
    _dismissFirstRunHint(repo);
    HapticFeedback.mediumImpact();
    repo.updateSettings(repo.settings.copyWith(assistantBubbleEnabled: false));

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: const Key('assistant-bubble-hidden-snackbar'),
        content: Text(
          tr.primary(
            'បានលាក់ប៊ូតុងជំនួយការ · អាចបើកវិញនៅ គណនី (Profile)',
            'Assistant bubble hidden · Re-enable anytime in Profile',
          ),
        ),
        action: SnackBarAction(
          label: tr.primary('មិនធ្វើវិញ', 'Undo'),
          onPressed: () {
            HapticFeedback.selectionClick();
            repo.updateSettings(
              repo.settings.copyWith(assistantBubbleEnabled: true),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openChatPanel(
    BuildContext context,
    AssistantController controller,
    Bilingual tr,
  ) async {
    final repo = ReportScope.read(context);
    _dismissFirstRunHint(repo);
    HapticFeedback.selectionClick();
    await showAssistantChatPanel(
      controller: controller,
      tr: tr,
      onHideBubble: () {
        if (mounted) _hideBubbleWithUndo(this.context, tr);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    final repo = ReportScope.of(context);
    final settings = repo.settings;
    final tr = Bilingual(settings.englishFirst);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final visible =
        settings.assistantBubbleEnabled &&
        controller.suppressCount == 0 &&
        controller.popupDepth == 0 &&
        !controller.isPanelOpen &&
        viewInsets.bottom == 0;

    _maybeTriggerFirstRunHint(repo, visible, reduceMotion);

    final isWide = mediaSize.width >= AssistantBubbleHost._wideBreakpoint;
    final minLeft = isWide
        ? AssistantBubbleHost._railClearance
        : AssistantBubbleHost._edgeMargin;
    final maxLeft =
        (mediaSize.width -
                AssistantBubbleHost.bubbleSize -
                AssistantBubbleHost._edgeMargin)
            .clamp(minLeft, double.infinity);

    final minTop = padding.top + 72.0;
    final bottomBarReserve = isWide ? 16.0 : 68.0;
    final maxTop =
        (mediaSize.height -
                padding.bottom -
                bottomBarReserve -
                AssistantBubbleHost.bubbleSize -
                16.0)
            .clamp(minTop, double.infinity);
    final travelHeight = (maxTop - minTop).clamp(0.0, double.infinity);

    final snappedLeft = settings.assistantBubbleOnLeft ? minLeft : maxLeft;
    final snappedTop =
        minTop +
        (travelHeight * settings.assistantBubbleYFraction.clamp(0.0, 1.0));

    final currentLeft = (_isDragging && _dragPosition != null)
        ? _dragPosition!.dx.clamp(minLeft, maxLeft)
        : snappedLeft;
    final currentTop = (_isDragging && _dragPosition != null)
        ? _dragPosition!.dy.clamp(minTop, maxTop)
        : snappedTop;

    final hasUnread = controller.chatController.hasUnreadReply;
    final isOffline = !repo.isOnline;

    final hideActionLabel = tr.primary('លាក់ប៊ូតុងជំនួយការ', 'Hide bubble');
    final bubbleSemanticLabel = hasUnread
        ? tr.primary(
            'បើកជំនួយការ AI · មានចម្លើយថ្មី',
            'Open AI assistant, new reply',
          )
        : tr.primary('បើកជំនួយការ AI', 'Open AI assistant');

    final bubbleWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: bubbleSemanticLabel,
        hint: tr.primary('សង្កត់ឲ្យយូរដើម្បីលាក់', 'Long press to hide'),
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: hideActionLabel): () =>
              _hideBubbleWithUndo(context, tr),
        },
        child: GestureDetector(
          key: const Key('assistant-bubble'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _openChatPanel(context, controller, tr),
          onLongPress: () => _hideBubbleWithUndo(context, tr),
          onPanStart: (_) {
            _dismissFirstRunHint(repo);
            setState(() {
              _isDragging = true;
              _dragPosition = Offset(currentLeft, currentTop);
            });
          },
          onPanUpdate: (details) {
            setState(() {
              final next =
                  (_dragPosition ?? Offset(currentLeft, currentTop)) +
                  details.delta;
              _dragPosition = Offset(
                next.dx.clamp(minLeft, maxLeft),
                next.dy.clamp(minTop, maxTop),
              );
            });
          },
          onPanEnd: (_) {
            final finalPos = _dragPosition ?? Offset(currentLeft, currentTop);
            final centerX = finalPos.dx + (AssistantBubbleHost.bubbleSize / 2);
            final snapLeft = centerX < (mediaSize.width / 2);
            final nextFraction = travelHeight <= 0
                ? 0.45
                : ((finalPos.dy - minTop) / travelHeight).clamp(0.0, 1.0);
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
            HapticFeedback.selectionClick();
            repo.updateSettings(
              settings.copyWith(
                assistantBubbleOnLeft: snapLeft,
                assistantBubbleYFraction: nextFraction,
              ),
            );
          },
          onPanCancel: () {
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
          },
          child: SizedBox(
            width: AssistantBubbleHost.bubbleSize,
            height: AssistantBubbleHost.bubbleSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  width: AssistantBubbleHost.bubbleSize,
                  height: AssistantBubbleHost.bubbleSize,
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 2,
                    ),
                    boxShadow: _isDragging
                        ? const [
                            BoxShadow(
                              color: Color(0x40004E43),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ]
                        : AppColors.fabShadow,
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      key: const Key('assistant-bubble-unread-dot'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.saffron,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                if (isOffline)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      key: const Key('assistant-bubble-offline-dot'),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.8),
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.saffron,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final showHintPill = visible && _showFirstRunHint && !_isDragging;
    final hintOnRight = settings.assistantBubbleOnLeft;

    return Stack(
      children: [
        if (showHintPill)
          Positioned(
            left: hintOnRight
                ? currentLeft + AssistantBubbleHost.bubbleSize + 8
                : null,
            right: hintOnRight ? null : (mediaSize.width - currentLeft) + 8,
            top: currentTop + 10,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    key: const Key('assistant-first-run-hint'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Text(
                      tr.primary(
                        'ត្រូវការជំនួយ? សួរខ្ញុំបាន!',
                        'Need help? Ask me',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: (_isDragging || reduceMotion)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: currentLeft,
          top: currentTop,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.72,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: visible
                ? Material(
                    key: const ValueKey('assistant-bubble-visible'),
                    type: MaterialType.transparency,
                    child: bubbleWidget,
                  )
                : const SizedBox.shrink(
                    key: ValueKey('assistant-bubble-hidden'),
                  ),
          ),
        ),
      ],
    );
  }
}
