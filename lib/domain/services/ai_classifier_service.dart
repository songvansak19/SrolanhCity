import '../models/report_models.dart';
import '../models/routing_result.dart';

/// Local Khmer and English keyword classifier for citizen issue descriptions.
///
/// Explicitly strips false-positive phrases such as "ភ្លើងស្តុប" (traffic light)
/// so pothole descriptions near intersections are not misclassified as broken
/// streetlights.
///
/// This classifier inspects **text only**—it never claims to have analyzed
/// pixels of an attached image (real image classification is performed by
/// `CivicAiService`).
abstract final class AiClassifierService {
  static const Map<IssueCategory, List<String>> _keywords = {
    IssueCategory.pothole: [
      'រណ្តៅ',
      'ផ្លូវខូច',
      'ផ្លូវប្រេះ',
      'ជង្ហុក',
      'កៅស៊ូផ្លូវ',
      'គ្រោះថ្នាក់ម៉ូតូ',
      'pothole',
      'crater',
      'road crack',
      'asphalt',
      'hole',
      'road damage',
    ],
    IssueCategory.streetlight: [
      'ភ្លើងផ្លូវ',
      'បង្គោលភ្លើង',
      'អំពូល',
      'ងងឹត',
      'ភ្លើងភ្លឹបភ្លែត',
      'ខ្សែភ្លើង',
      'streetlight',
      'street light',
      'lamp',
      'bulb',
      'dark',
      'flicker',
      'edc',
    ],
    IssueCategory.drain: [
      'លូ',
      'លិចទឹក',
      'ស្ទះ',
      'ទឹកជំនន់',
      'ទឹកកខ្វក់',
      'គម្របលូ',
      'drain',
      'flood',
      'clog',
      'sewer',
      'waterlog',
      'standing water',
    ],
    IssueCategory.trash: [
      'សំរាម',
      'កាកសំណល់',
      'ក្លិនស្អុយ',
      'ចាក់សំរាម',
      'គំនរសំរាម',
      'trash',
      'garbage',
      'waste',
      'dump',
      'litter',
      'rubbish',
    ],
  };

  /// Classifies a report strictly from its citizen-provided description text.
  static AiClassificationResult classify({
    required String description,
    required IssueCategory selectedCategory,
    bool hasCustomPhoto = false,
  }) {
    // Remove common landmark phrases that cause false positives.
    final normalized = description
        .toLowerCase()
        .replaceAll('ភ្លើងស្តុប', '')
        .replaceAll('traffic light', '')
        .replaceAll('traffic lights', '')
        .trim();

    if (normalized.isEmpty) {
      return AiClassificationResult(
        category: selectedCategory,
        confidencePercent: 0,
        khmerReason: 'ផ្អែកលើប្រភេទដែលអ្នកបានជ្រើស',
        englishReason: 'Selected manually',
        matchedFromText: false,
      );
    }

    final scores = <IssueCategory, int>{
      for (final category in IssueCategory.values) category: 0,
    };

    for (final MapEntry(key: category, value: words) in _keywords.entries) {
      for (final word in words) {
        if (normalized.contains(word)) {
          scores[category] = scores[category]! + 1;
        }
      }
    }

    IssueCategory? bestCategory;
    var bestScore = 0;
    for (final MapEntry(key: category, value: score) in scores.entries) {
      if (score > bestScore ||
          (score == bestScore && score > 0 && category == selectedCategory)) {
        bestScore = score;
        bestCategory = category;
      }
    }

    if (bestCategory != null && bestScore > 0) {
      final confidence = (86 + (bestScore * 4)).clamp(86, 97);
      return AiClassificationResult(
        category: bestCategory,
        confidencePercent: confidence,
        khmerReason: 'រកឃើញពីពាក្យគន្លឹះក្នុងការពិពណ៌នា',
        englishReason: 'Matched from your description keywords',
        matchedFromText: true,
      );
    }

    return AiClassificationResult(
      category: selectedCategory,
      confidencePercent: 0,
      khmerReason: 'ផ្អែកលើប្រភេទដែលអ្នកបានជ្រើស',
      englishReason: 'Selected manually',
      matchedFromText: false,
    );
  }
}
