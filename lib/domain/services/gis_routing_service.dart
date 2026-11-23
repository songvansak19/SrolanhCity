import 'package:latlong2/latlong.dart';

import '../../data/services/location_service.dart';
import '../../data/services/reverse_geocoding_service.dart';
import '../models/cambodia_locations.dart';
import '../models/report_models.dart';
import '../models/routing_result.dart';
import 'spatial_clustering_service.dart';

/// Administrative GIS boundary lookup & automatic ministry / provincial
/// department routing for all 25 Capital & Provinces of Cambodia, enriched with
/// live OpenStreetMap Nominatim reverse geocoding when online.
abstract final class GisRoutingService {
  static const List<PhnomPenhLandmark> landmarks = [
    PhnomPenhLandmark(
      center: LatLng(11.5564, 104.9282),
      khmerRoad: 'មហាវិថីព្រះនរោត្តម',
      englishRoad: 'Norodom Blvd',
      khmerSangkat: 'សង្កាត់ផ្សារថ្មី',
      englishSangkat: 'Sangkat Phsar Thmei',
      khmerKhan: 'ខណ្ឌដូនពេញ',
      englishKhan: 'Khan Daun Penh',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5620, 104.9228),
      khmerRoad: 'មហាវិថីព្រះមុនីវង្ស',
      englishRoad: 'Monivong Blvd',
      khmerSangkat: 'សង្កាត់បឹងរាំង',
      englishSangkat: 'Sangkat Boeung Raing',
      khmerKhan: 'ខណ្ឌដូនពេញ',
      englishKhan: 'Khan Daun Penh',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5498, 104.9210),
      khmerRoad: 'ផ្លូវលេខ ៣១០',
      englishRoad: 'Street 310',
      khmerSangkat: 'សង្កាត់បឹងកេងកង ១',
      englishSangkat: 'Sangkat BKK 1',
      khmerKhan: 'ខណ្ឌបឹងកេងកង',
      englishKhan: 'Khan Boeung Keng Kang',
      roadClass: RoadClass.commercial,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5656, 104.9142),
      khmerRoad: 'មហាវិថីកម្ពុជាក្រោម',
      englishRoad: 'Kampuchea Krom Blvd',
      khmerSangkat: 'សង្កាត់មិត្តភាព',
      englishSangkat: 'Sangkat Mittapheap',
      khmerKhan: 'ខណ្ឌ ៧ មករា',
      englishKhan: 'Khan 7 Makara',
      roadClass: RoadClass.secondary,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5730, 104.8990),
      khmerRoad: 'ផ្លូវលេខ ២៨៩',
      englishRoad: 'Street 289',
      khmerSangkat: 'សង្កាត់បឹងកក់ ១',
      englishSangkat: 'Sangkat Boeung Kak 1',
      khmerKhan: 'ខណ្ឌទួលគោក',
      englishKhan: 'Khan Toul Kork',
      roadClass: RoadClass.commercial,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5415, 104.9110),
      khmerRoad: 'ផ្លូវលេខ ២៧១',
      englishRoad: 'Street 271',
      khmerSangkat: 'សង្កាត់ទួលទំពូង ២',
      englishSangkat: 'Sangkat Toul Tompoung 2',
      khmerKhan: 'ខណ្ឌចំការមន',
      englishKhan: 'Khan Chamkarmon',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5680, 104.8810),
      khmerRoad: 'មហាវិថីសហព័ន្ធរុស្ស៊ី',
      englishRoad: 'Russian Federation Blvd',
      khmerSangkat: 'សង្កាត់ទឹកថ្លា',
      englishSangkat: 'Sangkat Teuk Thla',
      khmerKhan: 'ខណ្ឌសែនសុខ',
      englishKhan: 'Khan Sen Sok',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5845, 104.9335),
      khmerRoad: 'ផ្លូវជាតិលេខ ៦A',
      englishRoad: 'National Road 6A',
      khmerSangkat: 'សង្កាត់ជ្រោយចង្វារ',
      englishSangkat: 'Sangkat Chroy Changvar',
      khmerKhan: 'ខណ្ឌជ្រោយចង្វារ',
      englishKhan: 'Khan Chroy Changvar',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5290, 104.9380),
      khmerRoad: 'ផ្លូវជាតិលេខ ១',
      englishRoad: 'National Road 1',
      khmerSangkat: 'សង្កាត់ច្បារអំពៅ ១',
      englishSangkat: 'Sangkat Chbar Ampov 1',
      khmerKhan: 'ខណ្ឌច្បារអំពៅ',
      englishKhan: 'Khan Chbar Ampov',
      roadClass: RoadClass.majorArtery,
    ),
    PhnomPenhLandmark(
      center: LatLng(11.5315, 104.8920),
      khmerRoad: 'ផ្លូវវេងស្រេង',
      englishRoad: 'Veng Sreng Blvd',
      khmerSangkat: 'សង្កាត់ស្ទឹងមានជ័យ',
      englishSangkat: 'Sangkat Stung Meanchey',
      khmerKhan: 'ខណ្ឌមានជ័យ',
      englishKhan: 'Khan Meanchey',
      roadClass: RoadClass.commercial,
    ),
  ];

  /// Searches Phnom Penh streets/landmarks and all 25 provincial capitals
  /// offline for instant map navigation.
  static PhnomPenhLandmark? findLandmarkByQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final zone in landmarks) {
      if (zone.englishRoad.toLowerCase().contains(q) ||
          zone.khmerRoad.toLowerCase().contains(q) ||
          zone.englishKhan.toLowerCase().contains(q) ||
          zone.khmerKhan.toLowerCase().contains(q) ||
          zone.englishSangkat.toLowerCase().contains(q) ||
          zone.khmerSangkat.toLowerCase().contains(q)) {
        return zone;
      }
    }

    final province = CambodiaLocationCatalog.findProvinceByName(query);
    if (province != null) {
      final firstDistrict = province.districts.isNotEmpty
          ? province.districts.first
          : null;
      final firstSangkat =
          (firstDistrict != null && firstDistrict.sangkats.isNotEmpty)
          ? firstDistrict.sangkats.first
          : null;
      return PhnomPenhLandmark(
        center: province.center,
        khmerRoad: province.khmer,
        englishRoad: province.english,
        khmerSangkat: firstSangkat?.khmer ?? province.khmer,
        englishSangkat: firstSangkat?.english ?? province.english,
        khmerKhan: firstDistrict?.khmer ?? province.khmer,
        englishKhan: firstDistrict?.english ?? province.english,
        roadClass: RoadClass.commercial,
      );
    }
    return null;
  }

  /// Resolves administrative province, district, commune, road class, and
  /// responsible ministry/provincial agency from a GPS pin, optional live
  /// [geocodedPlace], and [category].
  static GisRoutingResult resolve({
    required LatLng coordinates,
    required IssueCategory category,
    GeocodedPlace? geocodedPlace,
  }) {
    final inCambodia = LocationService.isInsideCambodia(coordinates);

    if (!inCambodia) {
      final roadEn =
          geocodedPlace?.roadName ??
          'GPS (${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)})';
      final areaEn = geocodedPlace?.khan ?? 'Outside Cambodia';
      return GisRoutingResult(
        khmerSangkat: 'ក្រៅព្រំដែនកម្ពុជា',
        englishSangkat: geocodedPlace?.sangkat ?? 'Outside Cambodia',
        khmerKhan: areaEn,
        englishKhan: areaEn,
        khmerRoadName: roadEn,
        englishRoadName: roadEn,
        roadClass: RoadClass.secondary,
        khmerAgency: 'រង់ចាំផ្ទៀងផ្ទាត់តំបន់កម្ពុជា',
        englishAgency: 'Awaiting Cambodia Area Verification',
        provinceCode: 'outside_cambodia',
        khmerProvince: 'ក្រៅប្រទេសកម្ពុជា',
        englishProvince: 'Outside Cambodia',
      );
    }

    // 1. Determine nearest Phnom Penh landmark (for street-level Phnom Penh detail).
    var nearest = landmarks.first;
    var bestDistance = SpatialClusteringService.distanceMeters(
      coordinates,
      nearest.center,
    );

    for (final zone in landmarks.skip(1)) {
      final meters = SpatialClusteringService.distanceMeters(
        coordinates,
        zone.center,
      );
      if (meters < bestDistance) {
        bestDistance = meters;
        nearest = zone;
      }
    }

    final isWithinPhnomPenhZone = bestDistance <= 3500;

    // 2. Resolve Province across all 25 official Cambodia provinces.
    final resolvedProvince =
        CambodiaLocationCatalog.findProvinceByName(geocodedPlace?.province) ??
        CambodiaLocationCatalog.findProvinceByName(geocodedPlace?.khan) ??
        (isWithinPhnomPenhZone
            ? CambodiaLocationCatalog.phnomPenh
            : CambodiaLocationCatalog.nearestProvinceForPoint(coordinates));
    final isPhnomPenh =
        resolvedProvince.code == CambodiaLocationCatalog.phnomPenhCode;

    final inferredRoadName = geocodedPlace?.roadName;
    final inferredRoadClass = _inferRoadClass(
      inferredRoadName: inferredRoadName,
      fallback: isPhnomPenh && isWithinPhnomPenhZone
          ? nearest.roadClass
          : RoadClass.secondary,
    );

    final khmerRoad =
        inferredRoadName ??
        (isPhnomPenh && isWithinPhnomPenhZone
            ? nearest.khmerRoad
            : 'ផ្លូវ (${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)})');
    final englishRoad =
        inferredRoadName ??
        (isPhnomPenh && isWithinPhnomPenhZone
            ? nearest.englishRoad
            : 'Road (${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)})');

    final matchedDistrict =
        CambodiaLocationCatalog.findDistrictInProvince(
          resolvedProvince,
          geocodedPlace?.khan,
        ) ??
        CambodiaLocationCatalog.findDistrictInProvince(
          resolvedProvince,
          geocodedPlace?.displayName,
        );
    final matchedSangkat = matchedDistrict != null
        ? CambodiaLocationCatalog.findSangkatInKhan(
            matchedDistrict,
            geocodedPlace?.sangkat,
          )
        : null;

    final defaultProvincialDistrict = resolvedProvince.districts.isNotEmpty
        ? resolvedProvince.districts.first
        : null;
    final defaultProvincialSangkat =
        (defaultProvincialDistrict != null &&
            defaultProvincialDistrict.sangkats.isNotEmpty)
        ? defaultProvincialDistrict.sangkats.first
        : null;

    final String khmerKhan;
    final String englishKhan;
    final String khmerSangkat;
    final String englishSangkat;

    if (isPhnomPenh) {
      khmerKhan =
          matchedDistrict?.khmer ??
          (isWithinPhnomPenhZone
              ? nearest.khmerKhan
              : (geocodedPlace?.khan ?? 'រាជធានីភ្នំពេញ'));
      englishKhan = matchedDistrict != null
          ? 'Khan ${matchedDistrict.english}'
          : (geocodedPlace?.khan ??
                (isWithinPhnomPenhZone ? nearest.englishKhan : 'Phnom Penh'));
      khmerSangkat =
          matchedSangkat?.khmer ??
          (geocodedPlace?.sangkat != null && matchedDistrict != null
              ? 'សង្កាត់ ${geocodedPlace!.sangkat}'
              : (isWithinPhnomPenhZone
                    ? nearest.khmerSangkat
                    : (geocodedPlace?.sangkat ?? 'រាជធានីភ្នំពេញ')));
      englishSangkat = matchedSangkat != null
          ? 'Sangkat ${matchedSangkat.english}'
          : (geocodedPlace?.sangkat ??
                (isWithinPhnomPenhZone
                    ? nearest.englishSangkat
                    : 'Phnom Penh'));
    } else {
      khmerKhan =
          matchedDistrict?.khmer ??
          geocodedPlace?.khan ??
          defaultProvincialDistrict?.khmer ??
          resolvedProvince.khmer;
      englishKhan =
          matchedDistrict?.english ??
          geocodedPlace?.khan ??
          defaultProvincialDistrict?.english ??
          resolvedProvince.english;
      khmerSangkat =
          matchedSangkat?.khmer ??
          geocodedPlace?.sangkat ??
          defaultProvincialSangkat?.khmer ??
          resolvedProvince.khmer;
      englishSangkat =
          matchedSangkat?.english ??
          geocodedPlace?.sangkat ??
          defaultProvincialSangkat?.english ??
          resolvedProvince.english;
    }

    // 3. Route to Phnom Penh ministries/PPCH vs Provincial DPWT/EDC/Krong-Srok.
    final (khmerAgency, englishAgency) = isPhnomPenh
        ? switch ((category, inferredRoadClass)) {
            (IssueCategory.pothole, RoadClass.majorArtery) => (
              'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
              'Ministry of Public Works & Transport (MPWT)',
            ),
            (IssueCategory.pothole, _) => (
              'រដ្ឋបាលរាជធានីភ្នំពេញ · $khmerKhan',
              'Phnom Penh Capital Hall · $englishKhan',
            ),
            (IssueCategory.streetlight, _) => (
              'អគ្គិសនីកម្ពុជា (EDC)',
              'Electricité du Cambodge (EDC)',
            ),
            (IssueCategory.drain, _) => (
              'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ',
              'Dept. of Public Works & Drainage (PPCH)',
            ),
            (IssueCategory.trash, _) => (
              'រដ្ឋបាល$khmerKhan និងសេវាប្រមូលសំរាម',
              '$englishKhan Admin & Waste Management',
            ),
          }
        : switch ((category, inferredRoadClass)) {
            (IssueCategory.pothole, RoadClass.majorArtery) => (
              'ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)',
              'Ministry of Public Works & Transport (MPWT)',
            ),
            (IssueCategory.pothole, _) => (
              'មន្ទីរសាធារណការ និងដឹកជញ្ជូន ${resolvedProvince.khmer} (DPWT)',
              'Dept. of Public Works & Transport · ${resolvedProvince.english} (DPWT)',
            ),
            (IssueCategory.streetlight, _) => (
              'អគ្គិសនីកម្ពុជា · សាខា${resolvedProvince.khmer} (EDC)',
              'Electricité du Cambodge · ${resolvedProvince.english} (EDC)',
            ),
            (IssueCategory.drain, _) => (
              'មន្ទីរសាធារណការ និងប្រព័ន្ធលូ ${resolvedProvince.khmer}',
              '${resolvedProvince.english} Public Works & Drainage',
            ),
            (IssueCategory.trash, _) => (
              'រដ្ឋបាល$khmerKhan និងសេវាប្រមូលសំរាម (${resolvedProvince.shortKhmer})',
              '$englishKhan Admin & Waste Management (${resolvedProvince.english})',
            ),
          };

    return GisRoutingResult(
      khmerSangkat: khmerSangkat,
      englishSangkat: englishSangkat,
      khmerKhan: khmerKhan,
      englishKhan: englishKhan,
      khmerRoadName: khmerRoad,
      englishRoadName: englishRoad,
      roadClass: inferredRoadClass,
      khmerAgency: khmerAgency,
      englishAgency: englishAgency,
      provinceCode: resolvedProvince.code,
      khmerProvince: resolvedProvince.khmer,
      englishProvince: resolvedProvince.english,
    );
  }

  static RoadClass _inferRoadClass({
    required String? inferredRoadName,
    required RoadClass fallback,
  }) {
    final name = inferredRoadName?.toLowerCase() ?? '';
    if (name.isEmpty) return fallback;
    if (name.contains('blvd') ||
        name.contains('boulevard') ||
        name.contains('national road') ||
        name.contains('highway') ||
        name.contains('expressway') ||
        name.contains('nr1') ||
        name.contains('nr2') ||
        name.contains('nr3') ||
        name.contains('nr4') ||
        name.contains('nr5') ||
        name.contains('nr6') ||
        name.contains('nr7') ||
        name.contains('nr8') ||
        name.contains('271') ||
        name.contains('norodom') ||
        name.contains('monivong') ||
        name.contains('monireth') ||
        name.contains('mao tse toung') ||
        name.contains('sihanouk') ||
        name.contains('sothearos') ||
        name.contains('charles de gaulle') ||
        name.contains('kampuchea krom') ||
        name.contains('veng sreng') ||
        name.contains('hanoi') ||
        name.contains('russian') ||
        name.contains('sivutha') ||
        name.contains('ekareach')) {
      return RoadClass.majorArtery;
    }
    if (name.contains('alley') || name.contains('lane')) {
      return RoadClass.alley;
    }
    return fallback;
  }
}

class PhnomPenhLandmark {
  const PhnomPenhLandmark({
    required this.center,
    required this.khmerRoad,
    required this.englishRoad,
    required this.khmerSangkat,
    required this.englishSangkat,
    required this.khmerKhan,
    required this.englishKhan,
    required this.roadClass,
  });

  final LatLng center;
  final String khmerRoad;
  final String englishRoad;
  final String khmerSangkat;
  final String englishSangkat;
  final String khmerKhan;
  final String englishKhan;
  final RoadClass roadClass;
}
