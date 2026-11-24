import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/help/assistant_chat_view.dart';
import '../../features/help/help_center_page.dart';
import '../l10n.dart';
import '../report_scope.dart';
import '../theme.dart';
import 'assistant_scope.dart';

const double _wideChatPanelBreakpoint = 600.0;

/// Opens the floating AI Civic Assistant chat panel over the current route:
/// - **Phone (< 600 dp)**: modal bottom sheet (~78% height) with drag handle
/// - **Desktop / Web (>= 600 dp)**: sleek corner chat card anchored to the
///   bubble's active side
Future<void> showAssistantChatPanel({
  required AssistantController controller,
  required Bilingual tr,
  required VoidCallback onHideBubble,
}) async {
  final navigator = controller.navigatorKey.currentState;
  if (navigator == null || controller.isPanelOpen) return;

  final navContext = navigator.context;
  final size = MediaQuery.sizeOf(navContext);
  final isWide = size.width >= _wideChatPanelBreakpoint;
  final reduceMotion = MediaQuery.disableAnimationsOf(navContext);

  controller.setPanelOpen(true);
  try {
    if (!isWide) {
      await showModalBottomSheet<void>(
        context: navContext,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          final bottomInset = MediaQuery.viewInsetsOf(sheetCtx).bottom;
          final availableHeight = MediaQuery.sizeOf(sheetCtx).height;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (availableHeight * 0.78).clamp(320.0, 680.0),
              ),
              child: Material(
                key: const Key('assistant-chat-panel'),
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                clipBehavior: Clip.antiAlias,
                child: _AssistantPanelContent(
                  controller: controller,
                  navigator: navigator,
                  showDragHandle: true,
                  onHideBubble: onHideBubble,
                ),
              ),
            ),
          );
        },
      );
    } else {
      final repo = ReportScope.read(navContext);
      final alignLeft = repo.settings.assistantBubbleOnLeft;
      await showGeneralDialog<void>(
        context: navContext,
        barrierDismissible: true,
        barrierLabel: tr.primary('បិទជំនួយការ AI', 'Close AI assistant'),
        barrierColor: Colors.black.withValues(alpha: 0.22),
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        pageBuilder: (dialogCtx, _, _) {
          final bottomInset = MediaQuery.viewInsetsOf(dialogCtx).bottom;
          return SafeArea(
            child: Align(
              alignment: alignLeft
                  ? Alignment.bottomLeft
                  : Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  alignLeft ? 92 : 20,
                  20,
                  20,
                  20 + bottomInset,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 380,
                    maxHeight: 560,
                  ),
                  child: Material(
                    key: const Key('assistant-chat-panel'),
                    color: Colors.white,
                    elevation: 12,
                    shadowColor: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _AssistantPanelContent(
                        controller: controller,
                        navigator: navigator,
                        showDragHandle: false,
                        onHideBubble: onHideBubble,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (dialogCtx, animation, _, child) {
          if (reduceMotion) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              alignment: alignLeft
                  ? Alignment.bottomLeft
                  : Alignment.bottomRight,
              child: child,
            ),
          );
        },
      );
    }
  } finally {
    controller.setPanelOpen(false);
  }
}

enum _PanelMenuAction { newChat, openHelpCenter, hideBubble }

class _AssistantPanelContent extends StatelessWidget {
  const _AssistantPanelContent({
    required this.controller,
    required this.navigator,
    required this.showDragHandle,
    required this.onHideBubble,
  });

  final AssistantController controller;
  final NavigatorState navigator;
  final bool showDragHandle;
  final VoidCallback onHideBubble;

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final isAiBackendLive =
        repo.isOnline && controller.chatController.isBackendAiConfigured;
    final isOffline = !repo.isOnline;

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDragHandle)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, showDragHandle ? 6 : 12, 8, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        tr.primary(
                          'ជំនួយការ SrolanhCity',
                          'SrolanhCity Assistant',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isOffline
                            ? AppColors.saffronSoft
                            : isAiBackendLive
                            ? AppColors.tealSoft
                            : AppColors.mutedSurface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isOffline
                            ? tr.primary(
                                'ក្រៅបណ្តាញ · ឆ្លើយតបលើឧបករណ៍',
                                'Offline · On-device answers',
                              )
                            : isAiBackendLive
                            ? tr.primary(
                                'SrolanhCity AI · ផ្ទាល់',
                                'SrolanhCity AI · Live',
                              )
                            : tr.primary(
                                'ជំនួយការលើឧបករណ៍ · ប្រើក្រៅបណ្តាញបាន',
                                'On-device · Offline-ready',
                              ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isOffline
                              ? AppColors.saffronInk
                              : isAiBackendLive
                              ? AppColors.tealDark
                              : AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PanelMenuAction>(
                key: const Key('assistant-panel-menu-btn'),
                tooltip: tr.primary('ជម្រើសបន្ថែម', 'More options'),
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.ink),
                onSelected: (action) {
                  HapticFeedback.selectionClick();
                  switch (action) {
                    case _PanelMenuAction.newChat:
                      controller.chatController.clearConversation();
                    case _PanelMenuAction.openHelpCenter:
                      if (navigator.canPop()) navigator.pop();
                      navigator.push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const HelpCenterPage(),
                        ),
                      );
                    case _PanelMenuAction.hideBubble:
                      if (navigator.canPop()) navigator.pop();
                      onHideBubble();
                  }
                },
                itemBuilder: (menuCtx) => [
                  PopupMenuItem<_PanelMenuAction>(
                    key: const Key('assistant-menu-new-chat'),
                    value: _PanelMenuAction.newChat,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            tr.primary('សន្ទនាថ្មី', 'New chat'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<_PanelMenuAction>(
                    key: const Key('assistant-menu-help-center'),
                    value: _PanelMenuAction.openHelpCenter,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.help_outline_rounded,
                          size: 18,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            tr.primary(
                              'មជ្ឈមណ្ឌលជំនួយ និង 1190',
                              'Help Center & hotlines',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<_PanelMenuAction>(
                    key: const Key('assistant-menu-hide-bubble'),
                    value: _PanelMenuAction.hideBubble,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            tr.primary('លាក់ប៊ូតុងជំនួយការ', 'Hide bubble'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              IconButton(
                key: const Key('assistant-panel-close-btn'),
                tooltip: tr.primary('បិទ', 'Close'),
                icon: const Icon(Icons.close_rounded, color: AppColors.ink),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: AssistantChatView(
            controller: controller.chatController,
            compact: true,
            closePopupOnAction: true,
            navigatorOverride: navigator,
            inputKey: const Key('assistant-panel-input'),
            sendButtonKey: const Key('assistant-panel-send-btn'),
            promptKeyPrefix: 'assistant-panel-prompt',
          ),
        ),
      ],
    );
  }
}
