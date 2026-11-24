import 'package:latlong2/latlong.dart';

import '../services/priority_calculator.dart';
import '../services/relative_time_formatter.dart';
import 'cambodia_locations.dart';

/// Supported sort modes for Area News and My Reports lists.
enum ReportSortOption {
  newest(khmerLabel: 'ថ្មីបំផុត', englishLabel: 'Newest'),
  highestPriority(
    khmerLabel: 'ពិន្ទុអាទិភាពខ្ពស់',
    englishLabel: 'Priority score',
  ),
  mostAffected(
    khmerLabel: 'អ្នករងផលប៉ះពាល់ច្រើន',
    englishLabel: 'Most affected',
  );

  const ReportSortOption({
    required this.khmerLabel,
    required this.englishLabel,
  });

  final String khmerLabel;
  final String englishLabel;
}

/// Local-to-cloud synchronization state for offline resilience.
enum SyncStatus {
  synced,
  pendingSync;

  static SyncStatus fromName(String? name) {
    for (final value in SyncStatus.values) {
      if (value.name == name) return value;
    }
    return SyncStatus.synced;
  }
}

/// Supported civic infrastructure issue categories.
enum IssueCategory {
  pothole(
    khmerName: 'រណ្តៅផ្លូវ',
    englishName: 'Pothole',
    defaultAssetPath: 'assets/pothole-before.jpg',
    defaultKhmerTitle: 'រណ្តៅផ្លូវជ្រៅ',
    defaultEnglishTitle: 'Deep Pothole',
    sampleKhmerDescription:
        'រណ្តៅធំនៅកណ្តាលផ្លូវ ម៉ូតូជាច្រើនងាយធ្លាក់ពេលភ្លៀង',
    sampleEnglishDescription: 'Deep pothole in the middle of the road; motorbikes risk falling in rain.',
  ),
  streetlight(
    khmerName: 'ភ្លើងផ្លូវខូច',
    englishName: 'Streetlight',
    defaultAssetPath: 'assets/streetlight.jpg',
    defaultKhmerTitle: 'ភ្លើងផ្លូវមិនភ្លឺ',
    defaultEnglishTitle: 'Broken Streetlight',
    sampleKhmerDescription:
        'បង្គោលភ្លើងផ្លូវរលត់ ៣ ដើម ធ្វើឲ្យងងឹតខ្លាំងពេលយប់',
    sampleEnglishDescription:
        'Three streetlights are out, making the road very dark at night.',
  ),
  drain(
    khmerName: 'លូស្ទះ',
    englishName: 'Blocked Drain',
    defaultAssetPath: 'assets/drain.jpg',
    defaultKhmerTitle: 'លូស្ទះ និងលិចទឹក',
    defaultEnglishTitle: 'Blocked & Flooded Drain',
    sampleKhmerDescription: 'លូស្ទះសំរាម ទឹកដក់លិចផ្លូវរៀងរាល់ពេលភ្លៀងធ្លាក់',
    sampleEnglishDescription:
        'Drain blocked with debris, causing street flooding whenever it rains.',
  ),
  trash(
    khmerName: 'សំរាមខុសច្បាប់',
    englishName: 'Illegal Waste',
    defaultAssetPath: 'assets/trash.jpg',
    defaultKhmerTitle: 'គំនរសំរាមខុសច្បាប់',
    defaultEnglishTitle: 'Illegal Waste Dumping',
    sampleKhmerDescription:
        'មានគំនរសំរាមចោលក្បែរផ្លូវ មានក្លិនស្អុយ និងប៉ះពាល់សុខភាព',
    sampleEnglishDescription: 'Illegal garbage pile dumped roadside with strong odor affecting residents.',
  ),
  other(
    khmerName: 'បញ្ហាផ្សេងៗ',
    englishName: 'Other Issue',
    defaultAssetPath: null,
    defaultKhmerTitle: 'បញ្ហាហេដ្ឋារចនាសម្ព័ន្ធផ្សេងៗ',
    defaultEnglishTitle: 'Other Street Issue',
    sampleKhmerDescription: 'មានបញ្ហាហេដ្ឋារចនាសម្ព័ន្ធសាធារណៈត្រូវការជួសជុល',
    sampleEnglishDescription:
        'Public street infrastructure issue requiring attention.',
  );

  /// The 4 core categories shown in HomePage's 4-column quick-report bar.
  static const List<IssueCategory> primaryCategories = [
    pothole,
    streetlight,
    drain,
    trash,
  ];

  const IssueCategory({
    required this.khmerName,
    required this.englishName,
    required this.defaultAssetPath,
    required this.defaultKhmerTitle,
    required this.defaultEnglishTitle,
    required this.sampleKhmerDescription,
    required this.sampleEnglishDescription,
  });

  final String khmerName;
  final String englishName;
  final String? defaultAssetPath;
  final String defaultKhmerTitle;
  final String defaultEnglishTitle;
  final String sampleKhmerDescription;
  final String sampleEnglishDescription;

  /// Quick-tap Khmer + English preset tags tailored to each category.
  List<(String khmer, String english)> get presetTags => switch (this) {
    IssueCategory.pothole => const [
      ('ផ្លូវខូចធំ', 'Deep crater'),
      ('ដក់ទឹក', 'Water-filled'),
      ('គ្រោះថ្នាក់ម៉ូតូ', 'Motorbike hazard'),
      ('ជិតសាលារៀន', 'Near school'),
    ],
    IssueCategory.streetlight => const [
      ('ងងឹតពេលយប់', 'Dark at night'),
      ('ភ្លើងភ្លឹបភ្លែត', 'Flickering'),
      ('ខ្សែភ្លើងធ្លាក់', 'Loose wire'),
      ('គ្រោះថ្នាក់ចរាចរណ៍', 'Traffic risk'),
    ],
    IssueCategory.drain => const [
      ('លិចទឹក', 'Flooded'),
      ('ស្ទះសំរាម', 'Clogged debris'),
      ('ក្លិនស្អុយ', 'Bad odor'),
      ('គម្របលូខូច', 'Broken cover'),
    ],
    IssueCategory.trash => const [
      ('សំរាមគរច្រើន', 'Large pile'),
      ('ក្លិនស្អុយ', 'Bad odor'),
      ('បិទផ្លូវដើរ', 'Blocking sidewalk'),
      ('ជិតលំនៅឋាន', 'Near homes'),
    ],
    IssueCategory.other => const [
      ('ផ្លូវដើរខូច', 'Broken sidewalk'),
      ('ដើមឈើដួល', 'Fallen tree'),
      ('ផ្លាកសញ្ញាខូច', 'Damaged sign'),
      ('បញ្ហាសុវត្ថិភាព', 'Safety hazard'),
    ],
  };

  static IssueCategory fromName(String? name) {
    for (final value in IssueCategory.values) {
      if (value.name == name) return value;
    }
    return IssueCategory.pothole;
  }

  static IssueCategory fromIndex(int index) {
    if (index < 0 || index >= IssueCategory.values.length) {
      return IssueCategory.pothole;
    }
    return IssueCategory.values[index];
  }
}

/// 4-stage transparent report accountability lifecycle.
enum ReportStatus {
  submitted(
    stageNumber: 1,
    khmerLabel: 'បានដាក់ស្នើ',
    englishLabel: 'Submitted',
  ),
  scheduled(
    stageNumber: 2,
    khmerLabel: 'បានកំណត់កាលវិភាគ',
    englishLabel: 'Scheduled',
  ),
  crewDispatched(
    stageNumber: 3,
    khmerLabel: 'ក្រុមជួសជុលនៅទីតាំង',
    englishLabel: 'Crew On-Site',
  ),
  resolved(stageNumber: 4, khmerLabel: 'បានដោះស្រាយ', englishLabel: 'Resolved');

  const ReportStatus({
    required this.stageNumber,
    required this.khmerLabel,
    required this.englishLabel,
  });

  final int stageNumber;
  final String khmerLabel;
  final String englishLabel;

  static ReportStatus fromName(String? name) {
    for (final value in ReportStatus.values) {
      if (value.name == name) return value;
    }
    return ReportStatus.submitted;
  }
}

/// Road classification & traffic density factor (1–5 scale, 40% weight).
enum RoadClass {
  alley(trafficScore: 1, khmerLabel: 'ផ្លូវលំតូច', englishLabel: 'Quiet Alley'),
  residential(
    trafficScore: 2,
    khmerLabel: 'ផ្លូវលំនៅឋាន',
    englishLabel: 'Residential Street',
  ),
  secondary(
    trafficScore: 3,
    khmerLabel: 'ផ្លូវតភ្ជាប់រង',
    englishLabel: 'Secondary Road',
  ),
  commercial(
    trafficScore: 4,
    khmerLabel: 'ផ្លូវពាណិជ្ជកម្ម / ជិតសាលា',
    englishLabel: 'Busy Commercial Road',
  ),
  majorArtery(
    trafficScore: 5,
    khmerLabel: 'មហាវិថីសំខាន់',
    englishLabel: 'Major Artery',
  );

  const RoadClass({
    required this.trafficScore,
    required this.khmerLabel,
    required this.englishLabel,
  });

  final int trafficScore;
  final String khmerLabel;
  final String englishLabel;

  static RoadClass fromName(String? name) {
    for (final value in RoadClass.values) {
      if (value.name == name) return value;
    }
    return RoadClass.secondary;
  }
}

/// Result of the weighted 1–5 Priority Score calculation.
class PriorityBreakdown {
  const PriorityBreakdown({
    required this.trafficScore,
    required this.severityScore,
    required this.reportCountScore,
    required this.rawScore,
    required this.level,
  });

  final int trafficScore;
  final int severityScore;
  final int reportCountScore;
  final double rawScore;
  final int level;

  String get khmerLevelName => switch (level) {
    5 => 'បន្ទាន់បំផុត',
    4 => 'អាទិភាពខ្ពស់',
    3 => 'អាទិភាពមធ្យម',
    2 => 'អាទិភាពទាប',
    _ => 'កម្រិតស្រាល',
  };

  String get englishLevelName => switch (level) {
    5 => 'Critical',
    4 => 'High',
    3 => 'Medium',
    2 => 'Low',
    _ => 'Minor',
  };

  String get khmerSla => switch (level) {
    5 => 'ជួសជុលក្នុង ២៤ ម៉ោង',
    4 => 'គ្រោងជួសជុលក្នុង ២–៣ ថ្ងៃ',
    3 => 'ផែនការជួសជុលប្រចាំសប្តាហ៍',
    2 => 'ជួសជុលរួមជាមួយតំបន់ជិតខាង',
    _ => 'ថែទាំតាមរដូវកាល',
  };

  String get englishSla => switch (level) {
    5 => 'Dispatch within 24 hours',
    4 => 'Schedule within 2–3 days',
    3 => 'Weekly maintenance route',
    2 => 'Batch with nearby repairs',
    _ => 'Routine seasonal maintenance',
  };
}

/// Editable citizen profile stored locally on-device.
class UserProfile {
  const UserProfile({
    this.khmerName = 'ភ្ញៀវ',
    this.englishName = 'Guest',
    this.phoneNumber = '',
    this.khmerHomeArea = '',
    this.englishHomeArea = '',
    this.homeProvinceCode,
    this.avatarPhotoPath,
  });

  final String khmerName;
  final String englishName;
  final String phoneNumber;
  final String khmerHomeArea;
  final String englishHomeArea;
  final String? homeProvinceCode;
  final String? avatarPhotoPath;

  /// Whether the citizen has configured a home province or neighborhood.
  bool get hasHomeArea =>
      (homeProvinceCode != null && homeProvinceCode!.trim().isNotEmpty) ||
      khmerHomeArea.trim().isNotEmpty ||
      englishHomeArea.trim().isNotEmpty;

  /// Computes 1–2 uppercase initials from the English name (or fallback).
  String get initials {
    final parts = englishName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'G';
    if (parts.length == 1) {
      final word = parts.first;
      if (word.toLowerCase() == 'guest') return 'G';
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Privacy-friendly masked phone display (e.g., `+855 *** 881`), or empty.
  String get maskedPhone {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 6) return trimmed;
    final prefix = trimmed.startsWith('+')
        ? trimmed.substring(0, trimmed.length >= 4 ? 4 : 2)
        : trimmed.substring(0, 3);
    final suffix = trimmed.substring(trimmed.length - 3);
    return '$prefix *** $suffix';
  }

  UserProfile copyWith({
    String? khmerName,
    String? englishName,
    String? phoneNumber,
    String? khmerHomeArea,
    String? englishHomeArea,
    String? homeProvinceCode,
    bool clearHomeProvince = false,
    String? avatarPhotoPath,
    bool clearAvatar = false,
  }) {
    return UserProfile(
      khmerName: khmerName ?? this.khmerName,
      englishName: englishName ?? this.englishName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      khmerHomeArea: khmerHomeArea ?? this.khmerHomeArea,
      englishHomeArea: englishHomeArea ?? this.englishHomeArea,
      homeProvinceCode: clearHomeProvince
          ? null
          : (homeProvinceCode ?? this.homeProvinceCode),
      avatarPhotoPath: clearAvatar
          ? null
          : (avatarPhotoPath ?? this.avatarPhotoPath),
    );
  }

  Map<String, dynamic> toJson() => {
    'khmerName': khmerName,
    'englishName': englishName,
    'phoneNumber': phoneNumber,
    'khmerHomeArea': khmerHomeArea,
    'englishHomeArea': englishHomeArea,
    'homeProvinceCode': homeProvinceCode,
    'avatarPhotoPath': avatarPhotoPath,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final khName = (json['khmerName'] as String?) ?? 'ភ្ញៀវ';
    final enName = (json['englishName'] as String?) ?? 'Guest';
    final phone = (json['phoneNumber'] as String?) ?? '';
    final khArea = (json['khmerHomeArea'] as String?) ?? '';
    final enArea = (json['englishHomeArea'] as String?) ?? '';
    final avatar = json['avatarPhotoPath'] as String?;

    // Migrate untouched legacy seeded persona cleanly to Guest defaults.
    if (enName == 'Sovannarith' &&
        phone == '+855 12 345 881' &&
        enArea == 'Phsar Thmei, Daun Penh' &&
        avatar == null) {
      return const UserProfile();
    }

    return UserProfile(
      khmerName: khName,
      englishName: enName,
      phoneNumber: phone,
      khmerHomeArea: khArea,
      englishHomeArea: enArea,
      homeProvinceCode: json['homeProvinceCode'] as String?,
      avatarPhotoPath: avatar,
    );
  }
}

/// Unfinished report draft saved when exiting the Report Wizard mid-way.
class ReportDraft {
  const ReportDraft({
    required this.category,
    required this.severity,
    required this.description,
    required this.isAnonymous,
    required this.localPhotoPaths,
    this.voiceTranscript,
    this.voiceAudioPath,
    this.voiceAudioDurationSeconds,
  });

  final IssueCategory category;
  final int severity;
  final String description;
  final bool isAnonymous;
  final List<String> localPhotoPaths;
  final String? voiceTranscript;
  final String? voiceAudioPath;
  final int? voiceAudioDurationSeconds;

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'severity': severity,
    'description': description,
    'isAnonymous': isAnonymous,
    'localPhotoPaths': localPhotoPaths,
    'voiceTranscript': voiceTranscript,
    if (voiceAudioPath != null) 'voiceAudioPath': voiceAudioPath,
    if (voiceAudioDurationSeconds != null)
      'voiceAudioDurationSeconds': voiceAudioDurationSeconds,
  };

  factory ReportDraft.fromJson(Map<String, dynamic> json) {
    final rawPaths = json['localPhotoPaths'];
    final paths = rawPaths is List
        ? rawPaths.whereType<String>().toList()
        : const <String>[];
    return ReportDraft(
      category: IssueCategory.fromName(json['category'] as String?),
      severity: (json['severity'] as num?)?.toInt() ?? 3,
      description: (json['description'] as String?) ?? '',
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      localPhotoPaths: paths,
      voiceTranscript: json['voiceTranscript'] as String?,
      voiceAudioPath: json['voiceAudioPath'] as String?,
      voiceAudioDurationSeconds: (json['voiceAudioDurationSeconds'] as num?)
          ?.toInt(),
    );
  }
}

/// One step in the 4-stage live accountability timeline.
class TimelineEntry {
  const TimelineEntry({
    required this.stage,
    required this.khmerTitle,
    required this.englishTitle,
    required this.khmerSubtitle,
    required this.englishSubtitle,
    required this.complete,
    this.timestamp,
  });

  final ReportStatus stage;
  final String khmerTitle;
  final String englishTitle;
  final String khmerSubtitle;
  final String englishSubtitle;
  final bool complete;
  final DateTime? timestamp;

  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'khmerTitle': khmerTitle,
    'englishTitle': englishTitle,
    'khmerSubtitle': khmerSubtitle,
    'englishSubtitle': englishSubtitle,
    'complete': complete,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
  };

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final rawTs = json['timestamp'] as String?;
    return TimelineEntry(
      stage: ReportStatus.fromName(json['stage'] as String?),
      khmerTitle: (json['khmerTitle'] as String?) ?? '',
      englishTitle: (json['englishTitle'] as String?) ?? '',
      khmerSubtitle: (json['khmerSubtitle'] as String?) ?? '',
      englishSubtitle: (json['englishSubtitle'] as String?) ?? '',
      complete: (json['complete'] as bool?) ?? false,
      timestamp: rawTs == null ? null : DateTime.tryParse(rawTs),
    );
  }
}

/// How a citizen's "Affects me" community support was proximity-verified.
enum SupportVerificationTier {
  verifiedNearby,
  cityCommuter,
  homeResident;

  static SupportVerificationTier? fromName(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final value in SupportVerificationTier.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  String get khmerLabel => switch (this) {
    SupportVerificationTier.verifiedNearby => 'ផ្ទៀងផ្ទាត់ជិតទីតាំង',
    SupportVerificationTier.cityCommuter => 'អ្នកដំណើរក្នុងតំបន់',
    SupportVerificationTier.homeResident => 'អ្នករស់នៅក្នុងតំបន់',
  };

  String get englishLabel => switch (this) {
    SupportVerificationTier.verifiedNearby => 'Verified nearby',
    SupportVerificationTier.cityCommuter => 'City commuter',
    SupportVerificationTier.homeResident => 'Home district resident',
  };
}

/// One citizen's field description or follow-up note attached to a shared
/// Master Incident. Displayed with privacy-first badges (never exposing real
/// names, phone numbers, or user IDs on public reports).
class CitizenComment {
  const CitizenComment({
    required this.id,
    required this.text,
    required this.createdAt,
    this.isOriginalReporter = false,
    this.isCurrentUser = false,
    this.isAnonymous = false,
    this.severity,
    this.voiceTranscript,
    this.voiceAudioPath,
    this.voiceAudioDurationSeconds,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool isOriginalReporter;
  final bool isCurrentUser;
  final bool isAnonymous;
  final int? severity;
  final String? voiceTranscript;
  final String? voiceAudioPath;
  final int? voiceAudioDurationSeconds;

  bool get hasText => text.trim().isNotEmpty;

  CitizenComment copyWith({
    String? text,
    DateTime? createdAt,
    bool? isOriginalReporter,
    bool? isCurrentUser,
    bool? isAnonymous,
    int? severity,
    String? voiceTranscript,
    String? voiceAudioPath,
    int? voiceAudioDurationSeconds,
  }) {
    return CitizenComment(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      isOriginalReporter: isOriginalReporter ?? this.isOriginalReporter,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      severity: severity ?? this.severity,
      voiceTranscript: voiceTranscript ?? this.voiceTranscript,
      voiceAudioPath: voiceAudioPath ?? this.voiceAudioPath,
      voiceAudioDurationSeconds:
          voiceAudioDurationSeconds ?? this.voiceAudioDurationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'isOriginalReporter': isOriginalReporter,
    'isCurrentUser': isCurrentUser,
    'isAnonymous': isAnonymous,
    if (severity != null) 'severity': severity,
    if (voiceTranscript != null) 'voiceTranscript': voiceTranscript,
    if (voiceAudioPath != null) 'voiceAudioPath': voiceAudioPath,
    if (voiceAudioDurationSeconds != null)
      'voiceAudioDurationSeconds': voiceAudioDurationSeconds,
  };

  factory CitizenComment.fromJson(Map<String, dynamic> json) {
    return CitizenComment(
      id: (json['id'] as String?) ?? 'c-legacy',
      text: (json['text'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      isOriginalReporter: (json['isOriginalReporter'] as bool?) ?? false,
      isCurrentUser: (json['isCurrentUser'] as bool?) ?? false,
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      severity: (json['severity'] as num?)?.toInt(),
      voiceTranscript: json['voiceTranscript'] as String?,
      voiceAudioPath: json['voiceAudioPath'] as String?,
      voiceAudioDurationSeconds: (json['voiceAudioDurationSeconds'] as num?)
          ?.toInt(),
    );
  }
}

/// Master Incident representing one or more clustered citizen reports.
class CivicReport {
  /// Citizens may withdraw or quick-edit a report they created within 15 mins
  /// as long as authorities have not yet moved it past [ReportStatus.submitted].
  static const Duration withdrawalWindow = Duration(minutes: 15);

  const CivicReport({
    required this.id,
    required this.category,
    required this.khmerTitle,
    required this.englishTitle,
    required this.description,
    required this.khmerLocation,
    required this.englishLocation,
    required this.coordinates,
    this.provinceCode = CambodiaLocationCatalog.phnomPenhCode,
    this.khmerProvince = 'រាជធានីភ្នំពេញ',
    this.englishProvince = 'Phnom Penh',
    required this.roadClass,
    required this.severity,
    required this.affectedCitizens,
    required this.status,
    required this.khmerAgency,
    required this.englishAgency,
    required this.createdAt,
    required this.timeline,
    this.citizenComments = const [],
    this.photoAssetPath,
    this.localPhotoPath,
    this.additionalLocalPhotoPaths = const [],
    this.resolvedAfterAssetPath,
    this.isAnonymous = false,
    this.exifStripped = true,
    this.isMine = false,
    this.createdByCurrentUser = false,
    this.joinedByCurrentUser = false,
    this.userSupportTier,
    this.userSupportDistanceMeters,
    this.syncStatus = SyncStatus.synced,
    this.crewCode,
    this.voiceTranscript,
    this.voiceAudioPath,
    this.voiceAudioDurationSeconds,
    this.citizenRating,
    this.beforeDateLabel = '20 Nov',
    this.afterDateLabel = '22 Nov',
    this.fixedDurationKhmer = 'ជួសជុលរួចក្នុង ២ ថ្ងៃ',
    this.fixedDurationEnglish = 'Fixed in 2 days',
  });

  final String id;
  final IssueCategory category;
  final String khmerTitle;
  final String englishTitle;
  final String description;
  final String khmerLocation;
  final String englishLocation;
  final LatLng coordinates;
  final String provinceCode;
  final String khmerProvince;
  final String englishProvince;
  final RoadClass roadClass;
  final int severity;
  final int affectedCitizens;
  final ReportStatus status;
  final String khmerAgency;
  final String englishAgency;
  final String? photoAssetPath;
  final String? localPhotoPath;
  final List<String> additionalLocalPhotoPaths;
  final String? resolvedAfterAssetPath;
  final bool isAnonymous;
  final bool exifStripped;
  final bool isMine;
  final bool createdByCurrentUser;
  final bool joinedByCurrentUser;
  final SupportVerificationTier? userSupportTier;
  final double? userSupportDistanceMeters;
  final SyncStatus syncStatus;
  final String? crewCode;
  final String? voiceTranscript;
  final String? voiceAudioPath;
  final int? voiceAudioDurationSeconds;
  final int? citizenRating;
  final String beforeDateLabel;
  final String afterDateLabel;
  final String fixedDurationKhmer;
  final String fixedDurationEnglish;
  final DateTime createdAt;
  final List<TimelineEntry> timeline;
  final List<CitizenComment> citizenComments;

  /// All citizen comments/descriptions attached to this Master Incident.
  /// Synthesizes the original reporter's entry for legacy persisted reports
  /// that predate [citizenComments].
  List<CitizenComment> get effectiveComments {
    if (citizenComments.isNotEmpty) return citizenComments;
    return [
      CitizenComment(
        id: 'c-orig-$id',
        text: description.trim(),
        createdAt: createdAt,
        isOriginalReporter: true,
        isCurrentUser: createdByCurrentUser || (isMine && !joinedByCurrentUser),
        isAnonymous: isAnonymous,
        severity: severity,
        voiceTranscript: voiceTranscript,
      ),
    ];
  }

  /// Additional citizen comments beyond the primary entry (for "+N more" pills).
  int get extraCommentCount =>
      effectiveComments.length > 1 ? effectiveComments.length - 1 : 0;

  /// Citizens who confirmed/upvoted this incident without leaving a comment.
  int get silentSupporterCount {
    final diff = affectedCitizens - effectiveComments.length;
    return diff > 0 ? diff : 0;
  }

  List<String> get allLocalPhotoPaths => [
    if (localPhotoPath != null && localPhotoPath!.isNotEmpty) localPhotoPath!,
    ...additionalLocalPhotoPaths,
  ];

  PriorityBreakdown get priority => PriorityCalculator.calculate(
    trafficScore: roadClass.trafficScore,
    severityScore: severity,
    reportCount: affectedCitizens,
  );

  /// Remaining time during which the reporting citizen may remove or quick-edit
  /// this report. Returns [Duration.zero] once expired, locked, or not owned.
  Duration remainingWithdrawalTime({
    DateTime? now,
    Duration window = withdrawalWindow,
  }) {
    if (!createdByCurrentUser || status != ReportStatus.submitted) {
      return Duration.zero;
    }
    final reference = now ?? DateTime.now();
    final elapsed = reference.difference(createdAt);
    if (elapsed.isNegative) return window;
    final remaining = window - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the citizen can currently remove or quick-edit this report.
  bool canWithdraw({DateTime? now, Duration window = withdrawalWindow}) =>
      remainingWithdrawalTime(now: now, window: window) > Duration.zero;

  bool get hasDescription => description.trim().isNotEmpty;

  /// True if this report already belongs to the citizen (seeded/created/joined).
  bool get isContributedByCurrentUser =>
      isMine || createdByCurrentUser || joinedByCurrentUser;

  /// Whether this report was joined/supported by the citizen rather than
  /// created by them, and can still have its support undone.
  bool get canUndoSupport =>
      joinedByCurrentUser &&
      !createdByCurrentUser &&
      status != ReportStatus.resolved;

  CivicReport copyWith({
    IssueCategory? category,
    String? khmerTitle,
    String? englishTitle,
    String? description,
    String? khmerLocation,
    String? englishLocation,
    LatLng? coordinates,
    String? provinceCode,
    String? khmerProvince,
    String? englishProvince,
    RoadClass? roadClass,
    int? severity,
    int? affectedCitizens,
    ReportStatus? status,
    String? khmerAgency,
    String? englishAgency,
    String? photoAssetPath,
    String? localPhotoPath,
    List<String>? additionalLocalPhotoPaths,
    String? resolvedAfterAssetPath,
    bool? isAnonymous,
    bool? exifStripped,
    bool? isMine,
    bool? createdByCurrentUser,
    bool? joinedByCurrentUser,
    SupportVerificationTier? userSupportTier,
    double? userSupportDistanceMeters,
    bool clearUserSupportMeta = false,
    SyncStatus? syncStatus,
    String? crewCode,
    String? voiceTranscript,
    String? voiceAudioPath,
    int? voiceAudioDurationSeconds,
    int? citizenRating,
    String? beforeDateLabel,
    String? afterDateLabel,
    String? fixedDurationKhmer,
    String? fixedDurationEnglish,
    DateTime? createdAt,
    List<TimelineEntry>? timeline,
    List<CitizenComment>? citizenComments,
  }) {
    return CivicReport(
      id: id,
      category: category ?? this.category,
      khmerTitle: khmerTitle ?? this.khmerTitle,
      englishTitle: englishTitle ?? this.englishTitle,
      description: description ?? this.description,
      khmerLocation: khmerLocation ?? this.khmerLocation,
      englishLocation: englishLocation ?? this.englishLocation,
      coordinates: coordinates ?? this.coordinates,
      provinceCode: provinceCode ?? this.provinceCode,
      khmerProvince: khmerProvince ?? this.khmerProvince,
      englishProvince: englishProvince ?? this.englishProvince,
      roadClass: roadClass ?? this.roadClass,
      severity: severity ?? this.severity,
      affectedCitizens: affectedCitizens ?? this.affectedCitizens,
      status: status ?? this.status,
      khmerAgency: khmerAgency ?? this.khmerAgency,
      englishAgency: englishAgency ?? this.englishAgency,
      photoAssetPath: photoAssetPath ?? this.photoAssetPath,
      localPhotoPath: localPhotoPath ?? this.localPhotoPath,
      additionalLocalPhotoPaths:
          additionalLocalPhotoPaths ?? this.additionalLocalPhotoPaths,
      resolvedAfterAssetPath:
          resolvedAfterAssetPath ?? this.resolvedAfterAssetPath,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      exifStripped: exifStripped ?? this.exifStripped,
      isMine: isMine ?? this.isMine,
      createdByCurrentUser: createdByCurrentUser ?? this.createdByCurrentUser,
      joinedByCurrentUser: joinedByCurrentUser ?? this.joinedByCurrentUser,
      userSupportTier: clearUserSupportMeta
          ? null
          : (userSupportTier ?? this.userSupportTier),
      userSupportDistanceMeters: clearUserSupportMeta
          ? null
          : (userSupportDistanceMeters ?? this.userSupportDistanceMeters),
      syncStatus: syncStatus ?? this.syncStatus,
      crewCode: crewCode ?? this.crewCode,
      voiceTranscript: voiceTranscript ?? this.voiceTranscript,
      voiceAudioPath: voiceAudioPath ?? this.voiceAudioPath,
      voiceAudioDurationSeconds:
          voiceAudioDurationSeconds ?? this.voiceAudioDurationSeconds,
      citizenRating: citizenRating ?? this.citizenRating,
      beforeDateLabel: beforeDateLabel ?? this.beforeDateLabel,
      afterDateLabel: afterDateLabel ?? this.afterDateLabel,
      fixedDurationKhmer: fixedDurationKhmer ?? this.fixedDurationKhmer,
      fixedDurationEnglish: fixedDurationEnglish ?? this.fixedDurationEnglish,
      createdAt: createdAt ?? this.createdAt,
      timeline: timeline ?? this.timeline,
      citizenComments: citizenComments ?? this.citizenComments,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'khmerTitle': khmerTitle,
    'englishTitle': englishTitle,
    'description': description,
    'khmerLocation': khmerLocation,
    'englishLocation': englishLocation,
    'lat': coordinates.latitude,
    'lng': coordinates.longitude,
    'provinceCode': provinceCode,
    'khmerProvince': khmerProvince,
    'englishProvince': englishProvince,
    'roadClass': roadClass.name,
    'severity': severity,
    'affectedCitizens': affectedCitizens,
    'status': status.name,
    'khmerAgency': khmerAgency,
    'englishAgency': englishAgency,
    'photoAssetPath': photoAssetPath,
    'localPhotoPath': localPhotoPath,
    'additionalLocalPhotoPaths': additionalLocalPhotoPaths,
    'resolvedAfterAssetPath': resolvedAfterAssetPath,
    'isAnonymous': isAnonymous,
    'exifStripped': exifStripped,
    'isMine': isMine,
    'createdByCurrentUser': createdByCurrentUser,
    'joinedByCurrentUser': joinedByCurrentUser,
    'userSupportTier': userSupportTier?.name,
    'userSupportDistanceMeters': userSupportDistanceMeters,
    'syncStatus': syncStatus.name,
    'crewCode': crewCode,
    'voiceTranscript': voiceTranscript,
    if (voiceAudioPath != null) 'voiceAudioPath': voiceAudioPath,
    if (voiceAudioDurationSeconds != null)
      'voiceAudioDurationSeconds': voiceAudioDurationSeconds,
    'citizenRating': citizenRating,
    'beforeDateLabel': beforeDateLabel,
    'afterDateLabel': afterDateLabel,
    'fixedDurationKhmer': fixedDurationKhmer,
    'fixedDurationEnglish': fixedDurationEnglish,
    'createdAt': createdAt.toIso8601String(),
    'timeline': timeline.map((e) => e.toJson()).toList(),
    'citizenComments': citizenComments.map((c) => c.toJson()).toList(),
  };

  factory CivicReport.fromJson(Map<String, dynamic> json) {
    final rawTimeline = json['timeline'];
    final entries = rawTimeline is List
        ? rawTimeline
              .whereType<Map<String, dynamic>>()
              .map(TimelineEntry.fromJson)
              .toList()
        : const <TimelineEntry>[];
    final rawComments = json['citizenComments'];
    final comments = rawComments is List
        ? rawComments
              .whereType<Map<String, dynamic>>()
              .map(CitizenComment.fromJson)
              .toList()
        : const <CitizenComment>[];
    final rawExtras = json['additionalLocalPhotoPaths'];
    final extras = rawExtras is List
        ? rawExtras.whereType<String>().toList()
        : const <String>[];
    final rawCategory = IssueCategory.fromName(json['category'] as String?);
    final rawPhotoAsset = json['photoAssetPath'] as String?;
    final coords = LatLng(
      (json['lat'] as num?)?.toDouble() ?? 11.5564,
      (json['lng'] as num?)?.toDouble() ?? 104.9282,
    );
    final khLoc = (json['khmerLocation'] as String?) ?? '';
    final enLoc = (json['englishLocation'] as String?) ?? '';
    final inferredProvince = CambodiaLocationCatalog.inferProvince(
      provinceCode: json['provinceCode'] as String?,
      khmerLocation: khLoc,
      englishLocation: enLoc,
      coordinates: coords,
    );
    return CivicReport(
      id: (json['id'] as String?) ?? '#SC-00000',
      category: rawCategory,
      khmerTitle: (json['khmerTitle'] as String?) ?? '',
      englishTitle: (json['englishTitle'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      khmerLocation: khLoc,
      englishLocation: enLoc,
      coordinates: coords,
      provinceCode: (json['provinceCode'] as String?) ?? inferredProvince.code,
      khmerProvince:
          (json['khmerProvince'] as String?) ?? inferredProvince.khmer,
      englishProvince:
          (json['englishProvince'] as String?) ?? inferredProvince.english,
      roadClass: RoadClass.fromName(json['roadClass'] as String?),
      severity: (json['severity'] as num?)?.toInt() ?? 3,
      affectedCitizens: (json['affectedCitizens'] as num?)?.toInt() ?? 1,
      status: ReportStatus.fromName(json['status'] as String?),
      khmerAgency: (json['khmerAgency'] as String?) ?? '',
      englishAgency: (json['englishAgency'] as String?) ?? '',
      photoAssetPath: (rawPhotoAsset != null && rawPhotoAsset.isNotEmpty)
          ? rawPhotoAsset
          : rawCategory.defaultAssetPath,
      localPhotoPath: json['localPhotoPath'] as String?,
      additionalLocalPhotoPaths: extras,
      resolvedAfterAssetPath: json['resolvedAfterAssetPath'] as String?,
      isAnonymous: (json['isAnonymous'] as bool?) ?? false,
      exifStripped: (json['exifStripped'] as bool?) ?? true,
      isMine: (json['isMine'] as bool?) ?? false,
      createdByCurrentUser: (json['createdByCurrentUser'] as bool?) ?? false,
      joinedByCurrentUser: (json['joinedByCurrentUser'] as bool?) ?? false,
      userSupportTier: SupportVerificationTier.fromName(
        json['userSupportTier'] as String?,
      ),
      userSupportDistanceMeters: (json['userSupportDistanceMeters'] as num?)
          ?.toDouble(),
      syncStatus: SyncStatus.fromName(json['syncStatus'] as String?),
      crewCode: json['crewCode'] as String?,
      voiceTranscript: json['voiceTranscript'] as String?,
      voiceAudioPath: json['voiceAudioPath'] as String?,
      voiceAudioDurationSeconds: (json['voiceAudioDurationSeconds'] as num?)
          ?.toInt(),
      citizenRating: (json['citizenRating'] as num?)?.toInt(),
      beforeDateLabel: (json['beforeDateLabel'] as String?) ?? '20 Nov',
      afterDateLabel: (json['afterDateLabel'] as String?) ?? '22 Nov',
      fixedDurationKhmer:
          (json['fixedDurationKhmer'] as String?) ?? 'ជួសជុលរួចក្នុង ២ ថ្ងៃ',
      fixedDurationEnglish:
          (json['fixedDurationEnglish'] as String?) ?? 'Fixed in 2 days',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      timeline: entries,
      citizenComments: comments,
    );
  }
}

/// Notification alert tied to a Master Incident.
class AlertItem {
  const AlertItem({
    required this.id,
    required this.reportId,
    required this.khmerTitle,
    required this.englishTitle,
    required this.khmerSubtitle,
    required this.englishSubtitle,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String reportId;
  final String khmerTitle;
  final String englishTitle;
  final String khmerSubtitle;
  final String englishSubtitle;
  final DateTime createdAt;
  final bool isRead;

  String formattedTimeAgo({required bool englishFirst, DateTime? now}) =>
      RelativeTimeFormatter.formatRelative(
        createdAt,
        englishFirst: englishFirst,
        now: now,
      );

  AlertItem copyWith({bool? isRead}) {
    return AlertItem(
      id: id,
      reportId: reportId,
      khmerTitle: khmerTitle,
      englishTitle: englishTitle,
      khmerSubtitle: khmerSubtitle,
      englishSubtitle: englishSubtitle,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reportId': reportId,
    'khmerTitle': khmerTitle,
    'englishTitle': englishTitle,
    'khmerSubtitle': khmerSubtitle,
    'englishSubtitle': englishSubtitle,
    'createdAt': createdAt.toIso8601String(),
    'isRead': isRead,
  };

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.tryParse((json['createdAt'] as String?) ?? '');
    return AlertItem(
      id: (json['id'] as String?) ?? 'alert-0',
      reportId: (json['reportId'] as String?) ?? '#SC-20481',
      khmerTitle: (json['khmerTitle'] as String?) ?? '',
      englishTitle: (json['englishTitle'] as String?) ?? '',
      khmerSubtitle: (json['khmerSubtitle'] as String?) ?? '',
      englishSubtitle: (json['englishSubtitle'] as String?) ?? '',
      createdAt:
          parsedDate ??
          _inferLegacyTimestamp(json['englishTimeAgo'] as String?),
      isRead: (json['isRead'] as bool?) ?? false,
    );
  }

  /// Gracefully migrates older saved JSON alerts that lacked `createdAt`.
  static DateTime _inferLegacyTimestamp(String? legacyEnglish) {
    final now = DateTime.now();
    final raw = (legacyEnglish ?? '').toLowerCase();
    if (raw.contains('3 day')) return now.subtract(const Duration(days: 3));
    if (raw.contains('yesterday')) return now.subtract(const Duration(days: 1));
    if (raw.contains('1h')) return now.subtract(const Duration(hours: 1));
    if (raw.contains('5m')) return now.subtract(const Duration(minutes: 5));
    return now.subtract(const Duration(minutes: 2));
  }
}

/// User preferences shared across the whole app.
class AppSettings {
  /// Sentinel value for [newsKhanEnglish] indicating "All districts in active province".
  static const String allPhnomPenhKey = '__all__';

  /// Sentinel value for [newsProvinceCode] indicating "All Cambodia (25 provinces)".
  static const String allCambodiaKey = '__all_cambodia__';

  const AppSettings({
    this.englishFirst = false,
    this.notificationsEnabled = true,
    this.anonymousByDefault = false,
    this.newsProvinceCode,
    this.newsKhanEnglish,
    this.newsSangkatEnglish,
  });

  final bool englishFirst;
  final bool notificationsEnabled;
  final bool anonymousByDefault;
  final String? newsProvinceCode;
  final String? newsKhanEnglish;
  final String? newsSangkatEnglish;

  AppSettings copyWith({
    bool? englishFirst,
    bool? notificationsEnabled,
    bool? anonymousByDefault,
    String? newsProvinceCode,
    String? newsKhanEnglish,
    String? newsSangkatEnglish,
    bool clearNewsProvince = false,
    bool clearNewsArea = false,
    bool clearNewsSangkat = false,
  }) {
    return AppSettings(
      englishFirst: englishFirst ?? this.englishFirst,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      anonymousByDefault: anonymousByDefault ?? this.anonymousByDefault,
      newsProvinceCode: clearNewsArea || clearNewsProvince
          ? null
          : (newsProvinceCode ?? this.newsProvinceCode),
      newsKhanEnglish: clearNewsArea
          ? null
          : (newsKhanEnglish ?? this.newsKhanEnglish),
      newsSangkatEnglish: clearNewsArea || clearNewsSangkat
          ? null
          : (newsSangkatEnglish ?? this.newsSangkatEnglish),
    );
  }

  Map<String, dynamic> toJson() => {
    'englishFirst': englishFirst,
    'notificationsEnabled': notificationsEnabled,
    'anonymousByDefault': anonymousByDefault,
    'newsProvinceCode': newsProvinceCode,
    'newsKhanEnglish': newsKhanEnglish,
    'newsSangkatEnglish': newsSangkatEnglish,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      englishFirst: (json['englishFirst'] as bool?) ?? false,
      notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? true,
      anonymousByDefault: (json['anonymousByDefault'] as bool?) ?? false,
      newsProvinceCode: json['newsProvinceCode'] as String?,
      newsKhanEnglish: json['newsKhanEnglish'] as String?,
      newsSangkatEnglish: json['newsSangkatEnglish'] as String?,
    );
  }
}
