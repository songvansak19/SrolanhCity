import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/services/help_assistant_service.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import 'assistant_actions.dart';
import 'help_chat_controller.dart';

/// Reusable bilingual AI Civic Assistant chat surface rendered both inline on
/// [HelpCenterPage] (`compact: false`) and inside the floating chat panel
/// (`compact: true`).
class AssistantChatView extends StatefulWidget {
  const AssistantChatView({
    super.key,
    required this.controller,
    this.compact = false,
    this.closePopupOnAction = false,
    this.navigatorOverride,
    this.inputKey = const Key('help-chat-input'),
    this.sendButtonKey = const Key('help-chat-send-btn'),
    this.promptKeyPrefix = 'help-prompt',
  });

  final HelpChatController controller;
  final bool compact;
  final bool closePopupOnAction;
  final NavigatorState? navigatorOverride;
  final Key inputKey;
  final Key sendButtonKey;
  final String promptKeyPrefix;

  @override
  State<AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<AssistantChatView> {
  late final TextEditingController _inputController;
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _lastMessageCount = widget.controller.messages.length;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AssistantChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastMessageCount = widget.controller.messages.length;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final count = widget.controller.messages.length;
    if (widget.compact && count != _lastMessageCount) {
      _lastMessageCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final target = _scrollController.position.maxScrollExtent;
        if (reduceMotion) {
          _scrollController.jumpTo(target);
        } else {
          unawaited(
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
            ),
          );
        }
      });
    }
  }

  Future<void> _sendQuestion(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || widget.controller.isThinking) return;
    HapticFeedback.selectionClick();
    _inputController.clear();
    final repo = ReportScope.read(context);
    await widget.controller.send(text, repo);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        final isThinking = widget.controller.isThinking;

        Widget buildQuickPrompts() {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final prompt in HelpAssistantService.quickPrompts) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: Key('${widget.promptKeyPrefix}-${prompt.id}'),
                      label: Text(
                        tr.primary(prompt.khmerLabel, prompt.englishLabel),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _sendQuestion(
                        tr.primary(prompt.khmerLabel, prompt.englishLabel),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        List<Widget> buildMessageWidgets() {
          final navigator = widget.navigatorOverride ?? Navigator.of(context);
          final messenger = ScaffoldMessenger.maybeOf(context);
          return [
            for (final msg in messages) ...[
              _ChatBubble(
                message: msg,
                tr: tr,
                actionLabel: msg.suggestedAction == null
                    ? null
                    : AssistantActions.actionLabel(
                        msg.suggestedAction!,
                        msg.referencedReportId,
                        tr,
                      ),
                onAction: msg.suggestedAction == null
                    ? null
                    : () => AssistantActions.runSuggestedAction(
                        navigator: navigator,
                        action: msg.suggestedAction!,
                        reportId: msg.referencedReportId,
                        tr: tr,
                        messenger: messenger,
                        closePopupFirst: widget.closePopupOnAction,
                      ),
              ),
              const SizedBox(height: 8),
            ],
            if (isThinking)
              Semantics(
                container: true,
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.teal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tr.primary(
                          'កំពុងរៀបចំចម្លើយ...',
                          'Preparing answer...',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ];
        }

        Widget buildComposer() {
          return Row(
            children: [
              Expanded(
                child: TextField(
                  key: widget.inputKey,
                  controller: _inputController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendQuestion,
                  decoration: InputDecoration(
                    labelText: tr.primary('សួរជំនួយការ', 'Ask assistant'),
                    hintText: tr.primary(
                      'សួរសំណួរ ឬវាយ #SC-20481...',
                      'Ask a question or type #SC-20481...',
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: FilledButton(
                  key: widget.sendButtonKey,
                  onPressed: isThinking
                      ? null
                      : () => _sendQuestion(_inputController.text),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Tooltip(
                    message: tr.primary('ផ្ញើសំណួរ', 'Send question'),
                    child: const Icon(Icons.send_rounded, size: 19),
                  ),
                ),
              ),
            ],
          );
        }

        if (widget.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: buildQuickPrompts(),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  children: buildMessageWidgets(),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: buildComposer(),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildQuickPrompts(),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buildMessageWidgets(),
              ),
            ),
            const SizedBox(height: 6),
            buildComposer(),
          ],
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.tr,
    this.actionLabel,
    this.onAction,
  });

  final HelpChatMessage message;
  final Bilingual tr;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.teal : AppColors.paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && message.fromBackendAi) ...[
              Text(
                'SrolanhCity AI',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              message.display(tr).replaceAll('**', ''),
              style: TextStyle(
                fontSize: 12.8,
                height: 1.45,
                color: isUser ? Colors.white : AppColors.ink,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(48, 44),
                  side: BorderSide(
                    color: AppColors.teal.withValues(alpha: 0.5),
                  ),
                ),
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: AppColors.teal,
                ),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tealDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isUser) return bubble;
    return Semantics(container: true, liveRegion: true, child: bubble);
  }
}
