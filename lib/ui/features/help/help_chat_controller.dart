import 'package:flutter/foundation.dart';

import '../../../data/repositories/report_repository.dart';
import '../../../data/services/civic_ai_service.dart';
import '../../../domain/services/help_assistant_service.dart';
import '../../core/l10n.dart';

/// Immutable message rendered inside both the Help Center and floating
/// assistant chat panel.
class HelpChatMessage {
  const HelpChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.khmerText,
    this.englishText,
    this.fromBackendAi = false,
    this.suggestedAction,
    this.referencedReportId,
  });

  final String id;
  final bool isUser;
  final String text;
  final String? khmerText;
  final String? englishText;
  final bool fromBackendAi;
  final HelpSuggestedAction? suggestedAction;
  final String? referencedReportId;

  /// Returns the localized message text so seeded system messages react live
  /// when the user switches between Khmer-first and English-first.
  String display(Bilingual tr) {
    if (khmerText != null && englishText != null) {
      return tr.primary(khmerText!, englishText!);
    }
    return text;
  }
}

/// Shared conversation controller used by both [HelpCenterPage] and the
/// app-wide floating AI Assistant bubble so conversation history persists
/// seamlessly across tabs and screens.
class HelpChatController extends ChangeNotifier {
  HelpChatController({HelpAssistantService? assistant})
    : _assistant = assistant ?? HelpAssistantService() {
    _seedWelcomeMessage();
  }

  final HelpAssistantService _assistant;
  final List<HelpChatMessage> _messages = <HelpChatMessage>[];
  bool _isThinking = false;
  bool _hasUnreadReply = false;
  bool _isPanelVisible = false;
  int _nextMessageSeq = 0;

  List<HelpChatMessage> get messages =>
      List<HelpChatMessage>.unmodifiable(_messages);
  bool get isThinking => _isThinking;
  bool get hasUnreadReply => _hasUnreadReply;
  bool get isBackendAiConfigured => _assistant.isBackendAiConfigured;

  void _seedWelcomeMessage() {
    _messages
      ..clear()
      ..add(
        const HelpChatMessage(
          id: 'welcome',
          isUser: false,
          text: '',
          khmerText: 'សួស្តី! ខ្ញុំជាជំនួយការ SrolanhCity។ អ្នកអាចសួរអំពីការរាយការណ៍ ពិន្ទុអាទិភាព P1–P5 ការប្រើប្រាស់ក្រៅបណ្តាញ ឬវាយលេខសំបុត្រដូចជា #SC-20481។',
          englishText: 'Hello! I am the SrolanhCity Civic Assistant. Ask about reporting issues, Priority P1–P5, offline sync, ministries, or type a ticket ID like #SC-20481.',
        ),
      );
  }

  /// Tracks whether the chat surface is currently visible on screen so replies
  /// arriving after the user closes the panel raise the bubble's unread dot.
  void setPanelVisible(bool visible) {
    _isPanelVisible = visible;
    if (visible && _hasUnreadReply) {
      _hasUnreadReply = false;
      notifyListeners();
    }
  }

  void markRead() {
    if (!_hasUnreadReply) return;
    _hasUnreadReply = false;
    notifyListeners();
  }

  void clearConversation() {
    _isThinking = false;
    _hasUnreadReply = false;
    _seedWelcomeMessage();
    notifyListeners();
  }

  Future<void> send(String rawText, ReportRepository repo) async {
    final text = rawText.trim();
    if (text.isEmpty || _isThinking) return;

    final tr = Bilingual(repo.settings.englishFirst);
    final history = _messages
        .map(
          (m) => HelpChatTurn(
            role: m.isUser ? 'user' : 'assistant',
            text: m.display(tr),
          ),
        )
        .toList(growable: false);

    _messages.add(
      HelpChatMessage(id: 'u-${++_nextMessageSeq}', isUser: true, text: text),
    );
    _isThinking = true;
    notifyListeners();

    final reply = await _assistant.respond(
      message: text,
      history: history,
      repository: repo,
      englishFirst: repo.settings.englishFirst,
    );

    _isThinking = false;
    _messages.add(
      HelpChatMessage(
        id: 'a-${++_nextMessageSeq}',
        isUser: false,
        text: reply.text,
        fromBackendAi: reply.fromBackendAi,
        suggestedAction: reply.suggestedAction,
        referencedReportId: reply.referencedReportId,
      ),
    );
    if (!_isPanelVisible) {
      _hasUnreadReply = true;
    }
    notifyListeners();
  }
}
