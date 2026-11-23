import 'report_models.dart';

/// Result from the AI text & photo issue classifier.
class AiClassificationResult {
  const AiClassificationResult({
    required this.category,
    required this.confidencePercent,
    required this.khmerReason,
    required this.englishReason,
    required this.matchedFromText,
  });

  final IssueCategory category;
  final int confidencePercent;
  final String khmerReason;
  final String englishReason;
  final bool matchedFromText;
}

/// Result from matching GPS coordinates against Cambodia administrative zones.
class GisRoutingResult {
  const GisRoutingResult({
    required this.khmerSangkat,
    required this.englishSangkat,
    required this.khmerKhan,
    required this.englishKhan,
    required this.khmerRoadName,
    required this.englishRoadName,
    required this.roadClass,
    required this.khmerAgency,
    required this.englishAgency,
    this.provinceCode = 'phnom_penh',
    this.khmerProvince = 'រាជធានីភ្នំពេញ',
    this.englishProvince = 'Phnom Penh',
  });

  final String khmerSangkat;
  final String englishSangkat;
  final String khmerKhan;
  final String englishKhan;
  final String khmerRoadName;
  final String englishRoadName;
  final RoadClass roadClass;
  final String khmerAgency;
  final String englishAgency;
  final String provinceCode;
  final String khmerProvince;
  final String englishProvince;

  String get fullKhmerLocation => provinceCode == 'phnom_penh'
      ? '$khmerRoadName · $khmerSangkat, $khmerKhan'
      : '$khmerRoadName · $khmerSangkat, $khmerKhan, $khmerProvince';

  String get fullEnglishLocation => provinceCode == 'phnom_penh'
      ? '$englishRoadName · $englishSangkat, $englishKhan'
      : '$englishRoadName · $englishSangkat, $englishKhan, $englishProvince';
}

/// An existing open Master Incident found within the spatial clustering radius.
class DuplicateMatch {
  const DuplicateMatch({
    required this.masterReport,
    required this.distanceMeters,
  });

  final CivicReport masterReport;
  final double distanceMeters;
}

/// Outcome of submitting a citizen report (created new vs merged into Master).
class ReportSubmissionResult {
  const ReportSubmissionResult({
    required this.report,
    required this.mergedIntoExisting,
    this.alreadyReportedByUser = false,
    this.mergedDistanceMeters,
    this.submittedDescription,
  });

  final CivicReport report;
  final bool mergedIntoExisting;
  final bool alreadyReportedByUser;
  final double? mergedDistanceMeters;
  final String? submittedDescription;
}
