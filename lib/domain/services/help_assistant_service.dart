import '../../data/repositories/report_repository.dart';
import '../../data/services/civic_ai_service.dart';

/// One bilingual FAQ entry rendered in the Help Center accordion.
class HelpFaqItem {
  const HelpFaqItem({
    required this.id,
    required this.khmerQuestion,
    required this.englishQuestion,
    required this.khmerAnswer,
    required this.englishAnswer,
  });

  final String id;
  final String khmerQuestion;
  final String englishQuestion;
  final String khmerAnswer;
  final String englishAnswer;
}

/// Curated bilingual starter prompt chip for the Help Center AI chat.
class HelpQuickPrompt {
  const HelpQuickPrompt({
    required this.id,
    required this.khmerLabel,
    required this.englishLabel,
  });

  final String id;
  final String khmerLabel;
  final String englishLabel;
}

/// Hybrid SrolanhCity Civic Help Assistant:
/// 1. When `--dart-define=API_BASE_URL=...` is configured and online, calls
///    `POST /api/v1/ai/help-chat` (server owns LLM API keys & RAG).
/// 2. In client-only mode or offline, answers instantaneously in Khmer &
///    English using built-in civic knowledge PLUS live `#SC-XXXXX` ticket
///    lookup directly against [ReportRepository].
class HelpAssistantService {
  HelpAssistantService({CivicAiService? civicAiService})
    : _civicAiService = civicAiService ?? BackendCivicAiService();

  final CivicAiService _civicAiService;

  bool get isBackendAiConfigured => _civicAiService.isBackendConfigured;

  static const List<HelpQuickPrompt> quickPrompts = <HelpQuickPrompt>[
    HelpQuickPrompt(
      id: 'track',
      khmerLabel: 'ពិនិត្យស្ថានភាពរបាយការណ៍ខ្ញុំ',
      englishLabel: 'Track my reports',
    ),
    HelpQuickPrompt(
      id: 'priority',
      khmerLabel: 'របៀបគណនាអាទិភាព P1–P5',
      englishLabel: 'How is P1–P5 scored?',
    ),
    HelpQuickPrompt(
      id: 'offline',
      khmerLabel: 'រាយការណ៍ពេលគ្មានអ៊ីនធឺណិត',
      englishLabel: 'Offline reporting & voice',
    ),
    HelpQuickPrompt(
      id: 'ministries',
      khmerLabel: 'ក្រសួងណាជួសជុលភ្លើងផ្លូវ?',
      englishLabel: 'Who fixes streetlights?',
    ),
    HelpQuickPrompt(
      id: 'privacy',
      khmerLabel: 'ឯកជនភាព និង EXIF',
      englishLabel: 'Privacy & EXIF stripping',
    ),
  ];

  static const List<HelpFaqItem> faqs = <HelpFaqItem>[
    HelpFaqItem(
      id: 'faq-how-to-report',
      khmerQuestion: 'តើត្រូវរាយការណ៍បញ្ហាផ្លូវ ឬភ្លើងផ្លូវដោយរបៀបណា?',
      englishQuestion: 'How do I report a street, drain, or streetlight issue?',
      khmerAnswer: 'ចុចប៊ូតុង "+" នៅខាងក្រោម ឬជ្រើសប្រភេទបញ្ហានៅទំព័រដើម → (១) ថត ឬជ្រើសរូបថតរហូតដល់ ៣ សន្លឹក → (២) បញ្ជាក់កម្រិតគ្រោះថ្នាក់ វាយមតិ ឬថតសំឡេង → (៣) បញ្ជាក់ទីតាំងលើផែនទី ហើយចុចដាក់ស្នើ។',
      englishAnswer: 'Tap the "+" button on the bottom bar (or any quick category on Home) → (1) Take or pick up to 3 photos → (2) Set severity and add a note or voice memo → (3) Confirm the map pin and submit.',
    ),
    HelpFaqItem(
      id: 'faq-priority',
      khmerQuestion: 'តើពិន្ទុអាទិភាព P1 ដល់ P5 ត្រូវបានគណនាយ៉ាងដូចម្តេច?',
      englishQuestion: 'How are Priority Levels P1 to P5 calculated?',
      khmerAnswer: 'ពិន្ទុអាទិភាពគណនាដោយស្វ័យប្រវត្តិពីកត្តា ៣៖ ប្រភេទផ្លូវ និងចរាចរណ៍ (40%) + កម្រិតគ្រោះថ្នាក់ (30%) + ចំនួនប្រជាពលរដ្ឋរងផលប៉ះពាល់ (30%)។ កម្រិត P5 បន្ទាន់បំផុតមានគោលដៅបញ្ជូនក្រុមជួសជុលក្នុង ២៤ ម៉ោង។',
      englishAnswer: 'Priority combines 3 weighted factors: Road class & traffic (40%) + Hazard severity (30%) + Affected citizens count (30%). P5 Critical issues target crew dispatch within 24 hours.',
    ),
    HelpFaqItem(
      id: 'faq-ministries',
      khmerQuestion: 'តើក្រសួង និងអាជ្ញាធរណាខ្លះទទួលខុសត្រូវតាមប្រភេទបញ្ហា?',
      englishQuestion:
          'Which Cambodian ministries handle each infrastructure issue?',
      khmerAnswer: '• រណ្តៅផ្លូវ/មហាវិថី៖ ក្រសួងសាធារណការ (MPWT) ឬមន្ទីរសាធារណការខេត្ត (ខ្សែទូរស័ព្ទ 1190)\n• ភ្លើងផ្លូវខូច៖ អគ្គិសនីកម្ពុជា EDC (ខ្សែទូរស័ព្ទ 1298)\n• លូស្ទះ/លិចទឹក៖ មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានី-ខេត្ត\n• សំរាមខុសច្បាប់៖ អាជ្ញាធរសម្អាតក្រុង និងរដ្ឋបាលខណ្ឌ/ក្រុង (ទូទាំង ២៥ រាជធានី-ខេត្ត)។',
      englishAnswer: '• Potholes & roads: MPWT / Provincial DPWT (Hotline 1190)\n• Streetlights: Electricité du Cambodge — EDC (Hotline 1298)\n• Blocked drains & flooding: Municipal/Provincial Public Works & Drainage\n• Illegal waste: Municipal Sanitation Authority across all 25 provinces.',
    ),
    HelpFaqItem(
      id: 'faq-offline',
      khmerQuestion: 'តើកម្មវិធីដំណើរការពេលគ្មានអ៊ីនធឺណិត (Offline) ដែរឬទេ?',
      englishQuestion: 'Does SrolanhCity work offline?',
      khmerAnswer: 'បាទ/ចាស! របាយការណ៍ រូបថត និងសំឡេងរក្សាទុកក្នុងឧបករណ៍ជា "រង់ចាំផ្ញើ (Queued)" ហើយនឹងផ្ញើដោយស្វ័យប្រវត្តិភ្លាមៗពេលទូរស័ព្ទភ្ជាប់អ៊ីនធឺណិតវិញ — ទោះបីអ្នកបិទកម្មវិធីហើយបើកឡើងវិញក៏ដោយ។',
      englishAnswer: 'Yes! Reports, photos, and local voice memos save securely on your device as "Queued" and auto-sync the moment internet returns — even if you close and reopen the app later.',
    ),
    HelpFaqItem(
      id: 'faq-privacy-spoof',
      khmerQuestion:
          'តើឯកជនភាព និងប្រព័ន្ធទប់ស្កាត់ទីតាំងក្លែងក្លាយដំណើរការយ៉ាងណា?',
      englishQuestion: 'How do Privacy-by-Design and Anti-Spoof checks work?',
      khmerAnswer: 'ឈ្មោះ លេខទូរស័ព្ទ និងទិន្នន័យ EXIF ក្នុងរូបថតត្រូវបានលុបចេញដោយស្វ័យប្រវត្តិមុនរក្សាទុក ហើយមិនបង្ហាញលើផែនទីសាធារណៈឡើយ។ ការដាក់ស្នើរបាយការណ៍ក៏ផ្ទៀងផ្ទាត់ GPS ពិតប្រាកដក្នុងចម្ងាយ 15 គ.ម (ឬទីតាំង GPS ក្នុងរូបថត / តំបន់រស់នៅរបស់អ្នក) ដើម្បីការពារការបន្លំទីតាំងផងដែរ។',
      englishAnswer: 'Reporter names, phones, and camera EXIF metadata are automatically stripped and never shown on public pins. Submissions and votes verify genuine GPS within 15 km (or matching photo EXIF / your saved Home District) while blocking mock GPS and impossible travel.',
    ),
  ];

  /// Responds to a citizen's question in Khmer or English using Backend AI
  /// when connected & online, or the built-in bilingual Civic Assistant + live
  /// [ReportRepository] ticket lookup otherwise.
  Future<HelpChatReply> respond({
    required String message,
    required List<HelpChatTurn> history,
    required ReportRepository repository,
    required bool englishFirst,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return HelpChatReply(
        success: true,
        text: englishFirst
            ? 'Ask me anything about reporting street issues, Priority P1–P5, offline sync, or type a ticket ID like #SC-20481.'
            : 'សូមសួរសំណួរអំពីការរាយការណ៍បញ្ហា ពិន្ទុអាទិភាព P1–P5 ការប្រើប្រាស់ក្រៅបណ្តាញ ឬវាយលេខសំបុត្រដូចជា #SC-20481។',
      );
    }

    // Tier 1: Real backend LLM when API_BASE_URL is deployed & online.
    if (repository.isOnline && _civicAiService.isBackendConfigured) {
      final ctx = <String, dynamic>{
        'my_report_count': repository.myReports.length,
        'pending_sync_count': repository.pendingSyncCount,
        'recent_ticket_ids': repository.myReports
            .take(5)
            .map((r) => r.id)
            .toList(),
      };
      final backendReply = await _civicAiService.askHelpAssistant(
        message: trimmed,
        history: history,
        englishFirst: englishFirst,
        citizenContext: ctx,
      );
      if (backendReply.success && backendReply.text.isNotEmpty) {
        return backendReply;
      }
    }

    // Tier 2: Instant on-device bilingual Civic Assistant + live ticket lookup.
    return _respondOnDevice(
      message: trimmed,
      repository: repository,
      englishFirst: englishFirst,
    );
  }

  HelpChatReply _respondOnDevice({
    required String message,
    required ReportRepository repository,
    required bool englishFirst,
  }) {
    final lower = message.toLowerCase();
    final preferEnglish = _shouldReplyInEnglish(
      message,
      defaultEnglish: englishFirst,
    );

    // 1. Live ticket ID lookup (e.g., "#SC-20481" or "20481")
    final ticketMatch = RegExp(
      r'(?:#?sc-?)?(\d{5})',
      caseSensitive: false,
    ).firstMatch(message);
    if (ticketMatch != null) {
      final ticketId = '#SC-${ticketMatch.group(1)}';
      final report = repository.findById(ticketId);
      if (report != null) {
        final p = report.priority;
        final text = preferEnglish
            ? 'Ticket ${report.id} (${report.englishTitle}) is currently **${report.status.englishLabel}** · P${p.level} (${p.englishLevelName}).\n'
                  '• Assigned agency: ${report.englishAgency}\n'
                  '• Location: ${report.englishLocation}\n'
                  '• Affected citizens: ${report.affectedCitizens} · SLA: ${p.englishSla}'
            : 'សំបុត្រ ${report.id} (${report.khmerTitle}) បច្ចុប្បន្នស្ថិតក្នុងស្ថានភាព **${report.status.khmerLabel}** · P${p.level} (${p.khmerLevelName})។\n'
                  '• អង្គភាពទទួលខុសត្រូវ៖ ${report.khmerAgency}\n'
                  '• ទីតាំង៖ ${report.khmerLocation}\n'
                  '• អ្នករងផលប៉ះពាល់៖ ${report.affectedCitizens} នាក់ · គោលដៅ៖ ${p.khmerSla}';
        return HelpChatReply(
          success: true,
          text: text,
          suggestedAction: HelpSuggestedAction.openTicket,
          referencedReportId: report.id,
        );
      }
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'I could not find ticket $ticketId on this device yet. Open "My Reports" to inspect all active tickets.'
            : 'រកមិនឃើញលេខសំបុត្រ $ticketId ក្នុងឧបករណ៍នេះទេ។ សូមបើក "របាយការណ៍របស់ខ្ញុំ" ដើម្បីពិនិត្យមើលសំបុត្រទាំងអស់។',
        suggestedAction: HelpSuggestedAction.openMyReports,
      );
    }

    // 2. Track my reports / status overview
    if (_matchesAny(lower, const [
      'track',
      'my report',
      'status',
      'ticket',
      'ស្ថានភាព',
      'តាមដាន',
      'របាយការណ៍ខ្ញុំ',
      'របាយការណ៍របស់ខ្ញុំ',
    ])) {
      final mine = repository.myReports;
      final active = repository.activeTrackingReports;
      final pending = repository.pendingSyncCount;
      final latest = active.isNotEmpty
          ? active.first
          : (mine.isNotEmpty ? mine.first : null);
      if (latest != null) {
        final text = preferEnglish
            ? 'You currently have ${mine.length} report(s) (${active.length} active${pending > 0 ? ', $pending queued offline' : ''}).\n'
                  'Latest: ${latest.id} — ${latest.englishTitle} (${latest.status.englishLabel}, P${latest.priority.level}).\n'
                  'Tip: Type any ticket number like #SC-20481 for instant details.'
            : 'បច្ចុប្បន្នអ្នកមានរបាយការណ៍ ${mine.length} (${active.length} កំពុងតាមដាន${pending > 0 ? ' · $pending រង់ចាំផ្ញើក្រៅបណ្តាញ' : ''})។\n'
                  'ថ្មីបំផុត៖ ${latest.id} — ${latest.khmerTitle} (${latest.status.khmerLabel} · P${latest.priority.level})។\n'
                  'គន្លឹះ៖ អ្នកអាចវាយលេខសំបុត្រដូចជា #SC-20481 ដើម្បីមើលព័ត៌មានលម្អិតភ្លាមៗ។';
        return HelpChatReply(
          success: true,
          text: text,
          suggestedAction: HelpSuggestedAction.openTicket,
          referencedReportId: latest.id,
        );
      }
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'You have not submitted any reports yet. Tap below to report a street issue in under 30 seconds.'
            : 'អ្នកមិនទាន់មានរបាយការណ៍ទេ។ ចុចខាងក្រោមដើម្បីរាយការណ៍បញ្ហាក្នុងរយៈពេលក្រោម ៣០ វិនាទី។',
        suggestedAction: HelpSuggestedAction.openReportWizard,
      );
    }

    // 3. Priority Score P1–P5
    if (_matchesAny(lower, const [
      'priority',
      'score',
      'p1',
      'p2',
      'p3',
      'p4',
      'p5',
      'sla',
      'urgent',
      'អាទិភាព',
      'ពិន្ទុ',
      'បន្ទាន់',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'SrolanhCity calculates **Priority P1–P5** automatically using 3 transparent factors:\n'
                  '• Road class & traffic (40%)\n'
                  '• Hazard severity (30%)\n'
                  '• Affected citizens count (30%)\n'
                  'P5 Critical (≥ 4.5) targets dispatch within 24 hours, while P4 High targets 2–3 days.'
            : 'SrolanhCity គណនា **កម្រិតអាទិភាព P1–P5** ដោយស្វ័យប្រវត្តិតាមកត្តា ៣៖\n'
                  '• ប្រភេទផ្លូវ និងចរាចរណ៍ (40%)\n'
                  '• កម្រិតគ្រោះថ្នាក់ (30%)\n'
                  '• ចំនួនប្រជាពលរដ្ឋរងផលប៉ះពាល់ (30%)\n'
                  'កម្រិត P5 បន្ទាន់បំផុត (≥ 4.5) មានគោលដៅជួសជុលក្នុង ២៤ ម៉ោង និង P4 ក្នុង ២–៣ ថ្ងៃ។',
      );
    }

    // 4. Offline mode, syncing, voice memo
    if (_matchesAny(lower, const [
      'offline',
      'sync',
      'internet',
      'voice',
      'record',
      'audio',
      'queue',
      'ក្រៅបណ្តាញ',
      'អ៊ីនធឺណិត',
      'សំឡេង',
      'ថត',
      'រង់ចាំផ្ញើ',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'SrolanhCity works **offline**! Reports, photos, and local voice memos save safely on your device as **Queued** and auto-sync the moment your internet returns — even if you close and reopen the app.\n'
                  'For voice offline (or on Brave), tapping the mic automatically records a real local voice memo you can play back anytime.'
            : 'SrolanhCity ដំណើរការ **ក្រៅបណ្តាញ (Offline)** បាន! របាយការណ៍ រូបថត និងសំឡេងរក្សាទុកក្នុងឧបករណ៍ជា **រង់ចាំផ្ញើ (Queued)** ហើយផ្ញើស្វ័យប្រវត្តិភ្លាមៗពេលមានអ៊ីនធឺណិតវិញ — ទោះបីបិទហើយបើកកម្មវិធីឡើងវិញក៏ដោយ។\n'
                  'ពេលគ្មានអ៊ីនធឺណិត ការចុចមីក្រូហ្វូននឹងថតសំឡេងរក្សាទុកផ្ទាល់ ហើយអ្នកអាចចាក់ស្តាប់វិញបានភ្លាមៗ។',
        suggestedAction: HelpSuggestedAction.openReportWizard,
      );
    }

    // 5. Ministries / Streetlights / EDC / MPWT / Hotlines
    if (_matchesAny(lower, const [
      'streetlight',
      'light',
      'edc',
      'electric',
      'power',
      '1298',
      'ភ្លើង',
      'អគ្គិសនី',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'Broken streetlights and electrical hazards are automatically routed to **Electricité du Cambodge (EDC)**.\n'
                  'For urgent downed wires or outages, you can also call the **EDC Hotline 1298** directly.'
            : 'បញ្ហាភ្លើងផ្លូវខូច ឬគ្រោះថ្នាក់ខ្សែភ្លើងត្រូវបានបញ្ជូនដោយស្វ័យប្រវត្តិទៅ **អគ្គិសនីកម្ពុជា (EDC)**។\n'
                  'សម្រាប់ករណីបន្ទាន់ អ្នកក៏អាចហៅទៅ **ខ្សែទូរស័ព្ទ EDC 1298** ដោយផ្ទាល់ផងដែរ។',
        suggestedAction: HelpSuggestedAction.callPowerHotline1298,
      );
    }

    if (_matchesAny(lower, const [
      'ministry',
      'agency',
      'mpwt',
      'road',
      'pothole',
      'drain',
      'trash',
      'hotline',
      '1190',
      'emergency',
      'ក្រសួង',
      'អាជ្ញាធរ',
      'ផ្លូវ',
      'រណ្តៅ',
      'លូ',
      'សំរាម',
      'ទូរស័ព្ទ',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'SrolanhCity routes reports automatically across all **25 provinces** based on GPS & category:\n'
                  '• Roads & potholes → **MPWT / Provincial DPWT** (Hotline 1190)\n'
                  '• Streetlights → **EDC** (Hotline 1298)\n'
                  '• Drains & flooding → **Municipal Public Works & Drainage**\n'
                  '• Illegal waste → **Municipal Sanitation Authority**.'
            : 'SrolanhCity បញ្ជូនរបាយការណ៍ដោយស្វ័យប្រវត្តិទូទាំង **២៥ រាជធានី-ខេត្ត** តាម GPS និងប្រភេទបញ្ហា៖\n'
                  '• រណ្តៅផ្លូវ → **ក្រសួងសាធារណការ MPWT** (1190)\n'
                  '• ភ្លើងផ្លូវ → **អគ្គិសនីកម្ពុជា EDC** (1298)\n'
                  '• លូស្ទះ/លិចទឹក → **មន្ទីរសាធារណការ និងប្រព័ន្ធលូ**\n'
                  '• សំរាមខុសច្បាប់ → **អាជ្ញាធរសម្អាតក្រុង**។',
        suggestedAction: HelpSuggestedAction.callRoadHotline1190,
      );
    }

    // 6. Privacy, EXIF, Anonymous, Fake GPS / Anti-Spoof
    if (_matchesAny(lower, const [
      'privacy',
      'exif',
      'anonymous',
      'spoof',
      'fake',
      'gps',
      'security',
      'safe',
      'ឯកជន',
      'អនាមិក',
      'ក្លែងក្លាយ',
      'សុវត្ថិភាព',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'Your identity is protected by **Privacy-by-Design**:\n'
                  '• Public map pins never show your name, phone, or user ID.\n'
                  '• Camera EXIF metadata (GPS/device model) is stripped automatically before saving.\n'
                  '• Multi-layer anti-spoof locks geotagged/camera photos within 250 m of capture, checks duplicates at both pin and photo coordinates, enforces 15 km / Home District rules, and blocks fake GPS apps.'
            : 'អត្តសញ្ញាណរបស់អ្នកត្រូវបានការពារដោយ **ឯកជនភាពជាមូលដ្ឋាន**៖\n'
                  '• ផែនទីសាធារណៈមិនបង្ហាញឈ្មោះ លេខទូរស័ព្ទ ឬលេខសម្គាល់អ្នកឡើយ។\n'
                  '• ទិន្នន័យ EXIF ក្នុងរូបថតត្រូវបានលុបចេញដោយស្វ័យប្រវត្តិមុនរក្សាទុក។\n'
                  '• ប្រព័ន្ធការពារទីតាំងក្លែងក្លាយកំណត់រង្វង់ 250 ម៉ែត្រជុំវិញទីតាំងថតរូប ពិនិត្យរបាយការណ៍ស្ទួនទាំងម្ជុល និងរូបថត ផ្ទៀងផ្ទាត់ចម្ងាយ 15 គ.ម / តំបន់រស់នៅ និងទប់ស្កាត់កម្មវិធីបន្លំ GPS។',
      );
    }

    // 7. Edit / Delete / Withdraw / Profile
    if (_matchesAny(lower, const [
      'delete',
      'remove',
      'withdraw',
      'edit',
      'profile',
      'photo',
      'avatar',
      'លុប',
      'កែប្រែ',
      'គណនី',
      'រូបភាព',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? '• **Withdraw / Quick-Edit Report**: Within 15 minutes of submitting (while still in Submitted status), open your report on Tracking to edit or withdraw it.\n'
                  '• **Comments**: You can delete any extra note you added anytime via the red trash icon.\n'
                  '• **Profile & Photo**: Tap below to update your name, home province, or profile picture.'
            : '• **កែប្រែ ឬលុបរបាយការណ៍**៖ ក្នុងរយៈពេល ១៥ នាទីក្រោយដាក់ស្នើ (មុនអាជ្ញាធរទទួលផ្ទៀងផ្ទាត់) អ្នកអាចកែ ឬដករបាយការណ៍ចេញវិញបាន។\n'
                  '• **មតិបន្ថែម**៖ អ្នកអាចលុបមតិដែលអ្នកបានបន្ថែមគ្រប់ពេល។\n'
                  '• **គណនី និងរូបភាព**៖ ចុចខាងក្រោមដើម្បីប្តូរឈ្មោះ ខេត្ត ឬរូបភាពគណនី។',
        suggestedAction: HelpSuggestedAction.openEditProfile,
      );
    }

    // 8. How to report / general help fallback
    if (_matchesAny(lower, const [
      'report',
      'submit',
      'how',
      'start',
      'រាយការណ៍',
      'ដាក់ស្នើ',
      'របៀប',
    ])) {
      return HelpChatReply(
        success: true,
        text: preferEnglish
            ? 'Reporting takes 3 quick steps:\n'
                  '1. Capture or choose up to 3 photos\n'
                  '2. Pick severity & add a text or voice note (Khmer/EN)\n'
                  '3. Confirm the map pin and submit!\n'
                  'Tap below to open the Report Wizard now.'
            : 'ការរាយការណ៍មានតែ ៣ ជំហានខ្លីៗប៉ុណ្ណោះ៖\n'
                  '១. ថត ឬជ្រើសរូបភាពរហូតដល់ ៣ សន្លឹក\n'
                  '២. ជ្រើសកម្រិតគ្រោះថ្នាក់ និងបន្ថែមអក្សរ ឬសំឡេង (ខ្មែរ/EN)\n'
                  '៣. បញ្ជាក់ទីតាំងលើផែនទី រួចដាក់ស្នើ!\n'
                  'ចុចខាងក្រោមដើម្បីចាប់ផ្តើមរាយការណ៍ភ្លាម។',
        suggestedAction: HelpSuggestedAction.openReportWizard,
      );
    }

    // General friendly bilingual fallback
    return HelpChatReply(
      success: true,
      text: preferEnglish
          ? 'I can help you with:\n'
                '• Tracking any report (just type `#SC-20481` or `"Track my reports"`)\n'
                '• Priority Score `P1–P5` & ministry routing across all 25 provinces\n'
                '• Offline reporting, voice memos, privacy/EXIF & anti-spoof protection\n'
                '• Road emergency hotline `1190` or EDC power hotline `1298`'
          : 'ខ្ញុំអាចជួយអ្នកអំពី៖\n'
                '• តាមដានរបាយការណ៍ (វាយ `#SC-20481` ឬ `"ពិនិត្យស្ថានភាពរបាយការណ៍ខ្ញុំ"`)\n'
                '• របៀបគណនាអាទិភាព `P1–P5` និងការបញ្ជូនទៅក្រសួងទូទាំង ២៥ ខេត្ត\n'
                '• ការរាយការណ៍ក្រៅបណ្តាញ សំឡេង ឯកជនភាព EXIF និងការការពារ GPS ក្លែងក្លាយ\n'
                '• ខ្សែទូរស័ព្ទបន្ទាន់ផ្លូវ `1190` ឬអគ្គិសនី `1298`',
    );
  }

  static bool _shouldReplyInEnglish(
    String text, {
    required bool defaultEnglish,
  }) {
    var khmer = 0;
    var latin = 0;
    for (final r in text.runes) {
      if ((r >= 0x1780 && r <= 0x17FF) || (r >= 0x19E0 && r <= 0x19FF)) {
        khmer++;
      } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
        latin++;
      }
    }
    if (khmer > 0 && khmer >= latin) return false;
    if (latin > 0 && latin > khmer) return true;
    return defaultEnglish;
  }

  static bool _matchesAny(String needle, List<String> keywords) {
    for (final k in keywords) {
      if (needle.contains(k)) return true;
    }
    return false;
  }
}
