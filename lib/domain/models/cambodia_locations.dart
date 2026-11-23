import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Commune / Quarter option (`សង្កាត់` in urban areas, `ឃុំ` in rural districts).
class SangkatOption {
  const SangkatOption({required this.khmer, required this.english});

  final String khmer;
  final String english;
}

/// District / Municipality option (`ខណ្ឌ` in Phnom Penh, `ក្រុង` / `ស្រុក` in provinces).
class KhanOption {
  const KhanOption({
    required this.khmer,
    required this.english,
    required this.sangkats,
    this.aliases = const [],
  });

  final String khmer;
  final String english;
  final List<SangkatOption> sangkats;
  final List<String> aliases;
}

/// Official Cambodian Capital or Province (`រាជធានី` / `ខេត្ត`).
class ProvinceOption {
  const ProvinceOption({
    required this.code,
    required this.khmer,
    required this.english,
    required this.center,
    required this.districts,
    this.isCapital = false,
    this.defaultZoom = 12.6,
    this.aliases = const [],
  });

  final String code;
  final String khmer;
  final String english;
  final LatLng center;
  final List<KhanOption> districts;
  final bool isCapital;
  final double defaultZoom;
  final List<String> aliases;

  /// Compact Khmer label without the leading `ខេត្ត`/`រាជធានី` prefix for map bubbles.
  String get shortKhmer {
    if (khmer.startsWith('រាជធានី')) {
      return khmer.substring('រាជធានី'.length);
    }
    if (khmer.startsWith('ខេត្ត')) {
      return khmer.substring('ខេត្ត'.length);
    }
    return khmer;
  }
}

/// Structured nationwide Cambodia 3-level administrative directory covering all
/// 25 Capital & Provinces (ODC / NCDD hierarchy):
/// Level 1: `រាជធានី / ខេត្ត` (Capital / Province)
/// Level 2: `ខណ្ឌ / ក្រុង / ស្រុក` (Khan / Municipality / District)
/// Level 3: `សង្កាត់ / ឃុំ` (Sangkat / Commune)
abstract final class CambodiaLocationCatalog {
  static const String phnomPenhCode = 'phnom_penh';
  static const LatLng cambodiaOverviewCenter = LatLng(11.95, 104.45);
  static const double cambodiaOverviewZoom = 7.0;

  static const ProvinceOption phnomPenh = ProvinceOption(
    code: phnomPenhCode,
    khmer: 'រាជធានីភ្នំពេញ',
    english: 'Phnom Penh',
    center: LatLng(11.5564, 104.9282),
    isCapital: true,
    defaultZoom: 13.0,
    aliases: ['Phnom Penh', 'PhnomPenh', 'Krong Phnom Penh'],
    districts: [
      KhanOption(
        khmer: 'ខណ្ឌដូនពេញ',
        english: 'Daun Penh',
        aliases: ['Daun Penh', 'Doun Penh'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ផ្សារថ្មី', english: 'Phsar Thmei'),
          SangkatOption(khmer: 'សង្កាត់បឹងរាំង', english: 'Boeung Raing'),
          SangkatOption(khmer: 'សង្កាត់វត្តភ្នំ', english: 'Wat Phnom'),
          SangkatOption(khmer: 'សង្កាត់ជ័យជម្នះ', english: 'Chey Chumneas'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌបឹងកេងកង',
        english: 'Boeung Keng Kang',
        aliases: ['Boeung Keng Kang', 'Boeng Keng Kang', 'BKK'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់បឹងកេងកង ១', english: 'BKK 1'),
          SangkatOption(khmer: 'សង្កាត់បឹងកេងកង ២', english: 'BKK 2'),
          SangkatOption(khmer: 'សង្កាត់បឹងកេងកង ៣', english: 'BKK 3'),
          SangkatOption(
            khmer: 'សង្កាត់ទួលស្វាយព្រៃ ១',
            english: 'Toul Svay Prey 1',
          ),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌ ៧ មករា',
        english: '7 Makara',
        aliases: ['7 Makara', 'Prampir Meakkakra', 'Prampir Makara'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់មិត្តភាព', english: 'Mittapheap'),
          SangkatOption(khmer: 'សង្កាត់អូរឫស្សី ១', english: 'Orussey 1'),
          SangkatOption(khmer: 'សង្កាត់វាលវង់', english: 'Veal Vong'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌទួលគោក',
        english: 'Toul Kork',
        aliases: ['Toul Kork', 'Tuol Kouk', 'Tuol Kork'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់បឹងកក់ ១', english: 'Boeung Kak 1'),
          SangkatOption(khmer: 'សង្កាត់បឹងកក់ ២', english: 'Boeung Kak 2'),
          SangkatOption(khmer: 'សង្កាត់ផ្សារដេប៉ូ ១', english: 'Phsar Depo 1'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌចំការមន',
        english: 'Chamkarmon',
        aliases: ['Chamkarmon', 'Chamkar Mon'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ទួលទំពូង ២', english: 'Toul Tompoung'),
          SangkatOption(khmer: 'សង្កាត់ទន្លេបាសាក់', english: 'Tonle Bassac'),
          SangkatOption(
            khmer: 'សង្កាត់ផ្សារដើមថ្កូវ',
            english: 'Phsar Daeum Thkov',
          ),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌសែនសុខ',
        english: 'Sen Sok',
        aliases: ['Sen Sok', 'Saensokh', 'Saen Sokh'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ទឹកថ្លា', english: 'Teuk Thla'),
          SangkatOption(
            khmer: 'សង្កាត់ភ្នំពេញថ្មី',
            english: 'Phnom Penh Thmei',
          ),
          SangkatOption(khmer: 'សង្កាត់ក្រាំងធ្នង់', english: 'Krang Thnong'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌជ្រោយចង្វារ',
        english: 'Chroy Changvar',
        aliases: ['Chroy Changvar', 'Chrouy Changvar'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ជ្រោយចង្វារ', english: 'Chroy Changvar'),
          SangkatOption(khmer: 'សង្កាត់ព្រែកលៀប', english: 'Prek Leap'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌច្បារអំពៅ',
        english: 'Chbar Ampov',
        aliases: ['Chbar Ampov', 'Chba Ampov'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ច្បារអំពៅ ១', english: 'Chbar Ampov 1'),
          SangkatOption(khmer: 'សង្កាត់និរោធ', english: 'Niroth'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌមានជ័យ',
        english: 'Meanchey',
        aliases: ['Meanchey', 'Mean Chey'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ស្ទឹងមានជ័យ', english: 'Stung Meanchey'),
          SangkatOption(khmer: 'សង្កាត់បឹងទំពុន ១', english: 'Boeung Tumpun 1'),
        ],
      ),
      KhanOption(
        khmer: 'ខណ្ឌឫស្សីកែវ',
        english: 'Russey Keo',
        aliases: ['Russey Keo', 'Ruessei Kaev', 'Russei Keo'],
        sangkats: [
          SangkatOption(khmer: 'សង្កាត់ទួលសង្កែ ១', english: 'Toul Sangke 1'),
          SangkatOption(
            khmer: 'សង្កាត់គីឡូម៉ែត្រលេខ ៦',
            english: 'Kilometer 6',
          ),
        ],
      ),
    ],
  );

  /// All 25 official Capital & Provinces of Cambodia.
  static const List<ProvinceOption> provinces = [
    phnomPenh,
    ProvinceOption(
      code: 'siem_reap',
      khmer: 'ខេត្តសៀមរាប',
      english: 'Siem Reap',
      center: LatLng(13.3633, 103.8564),
      defaultZoom: 13.0,
      aliases: ['Siem Reap', 'Siemreap', 'Krong Siem Reap'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងសៀមរាប',
          english: 'Krong Siem Reap',
          aliases: ['Krong Siem Reap', 'Siem Reap City', 'Siem Reap'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ស្វាយដង្គំ', english: 'Svay Dangkum'),
            SangkatOption(khmer: 'សង្កាត់ស្លក្រាម', english: 'Sla Kram'),
            SangkatOption(khmer: 'សង្កាត់សាលាកំរើក', english: 'Sala Kamreuk'),
            SangkatOption(khmer: 'សង្កាត់គោកចក', english: 'Kouk Chak'),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកពួក',
          english: 'Puok',
          aliases: ['Puok', 'Srok Puok'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំពួក', english: 'Puok'),
            SangkatOption(khmer: 'ឃុំទឹកវិល', english: 'Tuek Vil'),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកប្រាសាទបាគង',
          english: 'Prasat Bakong',
          aliases: ['Prasat Bakong', 'Bakong'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំកណ្តែក', english: 'Kandaek'),
            SangkatOption(khmer: 'ឃុំបាគង', english: 'Bakong'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'preah_sihanouk',
      khmer: 'ខេត្តព្រះសីហនុ',
      english: 'Preah Sihanouk',
      center: LatLng(10.6275, 103.5221),
      defaultZoom: 13.0,
      aliases: [
        'Preah Sihanouk',
        'Sihanoukville',
        'Sihanouk',
        'Preah Sihanuk',
        'Krong Preah Sihanouk',
      ],
      districts: [
        KhanOption(
          khmer: 'ក្រុងព្រះសីហនុ',
          english: 'Krong Preah Sihanouk',
          aliases: ['Krong Preah Sihanouk', 'Sihanoukville', 'Preah Sihanouk'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់លេខ ៤', english: 'Sangkat 4'),
            SangkatOption(khmer: 'សង្កាត់លេខ ២', english: 'Sangkat 2'),
            SangkatOption(khmer: 'សង្កាត់លេខ ៣', english: 'Sangkat 3'),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកព្រៃនប់',
          english: 'Prey Nob',
          aliases: ['Prey Nob', 'Prey Nup'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំវាលរេញ', english: 'Veal Renh'),
            SangkatOption(khmer: 'ឃុំរាម', english: 'Ream'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'battambang',
      khmer: 'ខេត្តបាត់ដំបង',
      english: 'Battambang',
      center: LatLng(13.0957, 103.2022),
      defaultZoom: 13.0,
      aliases: ['Battambang', 'Batdambang', 'Bat Dambang'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងបាត់ដំបង',
          english: 'Krong Battambang',
          aliases: ['Krong Battambang', 'Battambang'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ស្វាយប៉ោ', english: 'Svay Por'),
            SangkatOption(khmer: 'សង្កាត់រតនៈ', english: 'Rattanak'),
            SangkatOption(
              khmer: 'សង្កាត់ព្រែកព្រះស្តេច',
              english: 'Prek Preah Sdach',
            ),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកសង្កែ',
          english: 'Sangkae',
          aliases: ['Sangkae', 'Sangke'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំនរា', english: 'Norea'),
            SangkatOption(khmer: 'ឃុំកំពង់ព្រះ', english: 'Kampong Preah'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kampot',
      khmer: 'ខេត្តកំពត',
      english: 'Kampot',
      center: LatLng(10.6104, 104.1814),
      defaultZoom: 13.0,
      aliases: ['Kampot', 'Kompot'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងកំពត',
          english: 'Krong Kampot',
          aliases: ['Krong Kampot', 'Kampot'],
          sangkats: [
            SangkatOption(
              khmer: 'សង្កាត់កំពង់កណ្តាល',
              english: 'Kampong Kandal',
            ),
            SangkatOption(khmer: 'សង្កាត់កំពង់បាយ', english: 'Kampong Bay'),
            SangkatOption(
              khmer: 'សង្កាត់អណ្តូងខ្មែរ',
              english: 'Andoung Khmer',
            ),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកទឹកឈូ',
          english: 'Teuk Chhou',
          aliases: ['Teuk Chhou', 'Tuek Chhou'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំព្រែកត្នោត', english: 'Prek Tnoat'),
            SangkatOption(khmer: 'ឃុំម៉ាក់ប្រាង្គ', english: 'Makprang'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kandal',
      khmer: 'ខេត្តកណ្តាល',
      english: 'Kandal',
      center: LatLng(11.4833, 104.9500),
      defaultZoom: 12.6,
      aliases: ['Kandal', 'Ta Khmau', 'Takhmao'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងតាខ្មៅ',
          english: 'Krong Ta Khmau',
          aliases: ['Ta Khmau', 'Takhmao', 'Krong Ta Khmau'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់តាខ្មៅ', english: 'Ta Khmau'),
            SangkatOption(khmer: 'សង្កាត់ព្រែកហូរ', english: 'Prek Ho'),
          ],
        ),
        KhanOption(
          khmer: 'ស្រុកកៀនស្វាយ',
          english: 'Kien Svay',
          aliases: ['Kien Svay'],
          sangkats: [
            SangkatOption(khmer: 'ឃុំគគីរ', english: 'Kokir'),
            SangkatOption(khmer: 'ឃុំដីឥដ្ឋ', english: 'Dei Edth'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kampong_cham',
      khmer: 'ខេត្តកំពង់ចាម',
      english: 'Kampong Cham',
      center: LatLng(11.9934, 105.4635),
      aliases: ['Kampong Cham', 'Kompong Cham'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងកំពង់ចាម',
          english: 'Krong Kampong Cham',
          aliases: ['Krong Kampong Cham', 'Kampong Cham'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់វាលវង់', english: 'Veal Vong'),
            SangkatOption(khmer: 'សង្កាត់កំពង់ចាម', english: 'Kampong Cham'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'banteay_meanchey',
      khmer: 'ខេត្តបន្ទាយមានជ័យ',
      english: 'Banteay Meanchey',
      center: LatLng(13.5859, 102.9737),
      aliases: ['Banteay Meanchey', 'Sisophon', 'Poipet'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងសិរីសោភ័ណ',
          english: 'Krong Serei Saophoan',
          aliases: ['Serei Saophoan', 'Sisophon'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ព្រះពន្លា', english: 'Preah Ponlea'),
          ],
        ),
        KhanOption(
          khmer: 'ក្រុងប៉ោយប៉ែត',
          english: 'Krong Poipet',
          aliases: ['Poipet', 'Paoy Paet'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ប៉ោយប៉ែត', english: 'Poipet'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'takeo',
      khmer: 'ខេត្តតាកែវ',
      english: 'Takeo',
      center: LatLng(10.9908, 104.7850),
      aliases: ['Takeo', 'Takaeo', 'Doun Kaev'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងដូនកែវ',
          english: 'Krong Doun Kaev',
          aliases: ['Doun Kaev', 'Takeo'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់រកាក្នុង', english: 'Roka Knong'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kampong_speu',
      khmer: 'ខេត្តកំពង់ស្ពឺ',
      english: 'Kampong Speu',
      center: LatLng(11.4533, 104.5209),
      aliases: ['Kampong Speu', 'Kompong Speu', 'Chbar Mon'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងច្បារមន',
          english: 'Krong Chbar Mon',
          aliases: ['Chbar Mon', 'Kampong Speu'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ច្បារមន', english: 'Chbar Mon'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kampong_chhnang',
      khmer: 'ខេត្តកំពង់ឆ្នាំង',
      english: 'Kampong Chhnang',
      center: LatLng(12.2500, 104.6667),
      aliases: ['Kampong Chhnang', 'Kompong Chhnang'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងកំពង់ឆ្នាំង',
          english: 'Krong Kampong Chhnang',
          aliases: ['Krong Kampong Chhnang', 'Kampong Chhnang'],
          sangkats: [
            SangkatOption(
              khmer: 'សង្កាត់ផ្សារឆ្នាំង',
              english: 'Phsar Chhnang',
            ),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kampong_thom',
      khmer: 'ខេត្តកំពង់ធំ',
      english: 'Kampong Thom',
      center: LatLng(12.7111, 104.8887),
      aliases: ['Kampong Thom', 'Kompong Thom', 'Stueng Saen'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងស្ទឹងសែន',
          english: 'Krong Stueng Saen',
          aliases: ['Stueng Saen', 'Stung Sen', 'Kampong Thom'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់កំពង់រទេះ', english: 'Kampong Roteh'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'pursat',
      khmer: 'ខេត្តពោធិ៍សាត់',
      english: 'Pursat',
      center: LatLng(12.5388, 103.9192),
      aliases: ['Pursat', 'Pousat'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងពោធិ៍សាត់',
          english: 'Krong Pursat',
          aliases: ['Krong Pursat', 'Pursat'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ផ្ទះព្រៃ', english: 'Phteah Prey'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'prey_veng',
      khmer: 'ខេត្តព្រៃវែង',
      english: 'Prey Veng',
      center: LatLng(11.4868, 105.3253),
      aliases: ['Prey Veng'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងព្រៃវែង',
          english: 'Krong Prey Veng',
          aliases: ['Krong Prey Veng', 'Prey Veng'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់កំពង់លាវ', english: 'Kampong Leav'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'svay_rieng',
      khmer: 'ខេត្តស្វាយរៀង',
      english: 'Svay Rieng',
      center: LatLng(11.0879, 105.7993),
      aliases: ['Svay Rieng', 'Bavet'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងស្វាយរៀង',
          english: 'Krong Svay Rieng',
          aliases: ['Krong Svay Rieng', 'Svay Rieng'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ស្វាយរៀង', english: 'Svay Rieng'),
          ],
        ),
        KhanOption(
          khmer: 'ក្រុងបាវិត',
          english: 'Krong Bavet',
          aliases: ['Bavet'],
          sangkats: [SangkatOption(khmer: 'សង្កាត់បាវិត', english: 'Bavet')],
        ),
      ],
    ),
    ProvinceOption(
      code: 'tbong_khmum',
      khmer: 'ខេត្តត្បូងឃ្មុំ',
      english: 'Tbong Khmum',
      center: LatLng(11.8891, 105.8760),
      aliases: ['Tbong Khmum', 'Tboung Khmum', 'Suong'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងសួង',
          english: 'Krong Suong',
          aliases: ['Suong', 'Tbong Khmum'],
          sangkats: [SangkatOption(khmer: 'សង្កាត់សួង', english: 'Suong')],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kep',
      khmer: 'ខេត្តកែប',
      english: 'Kep',
      center: LatLng(10.4829, 104.3167),
      aliases: ['Kep', 'Kaeb'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងកែប',
          english: 'Krong Kep',
          aliases: ['Krong Kep', 'Kep'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់កែប', english: 'Kep'),
            SangkatOption(khmer: 'សង្កាត់ព្រៃធំ', english: 'Prey Thom'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'koh_kong',
      khmer: 'ខេត្តកោះកុង',
      english: 'Koh Kong',
      center: LatLng(11.6153, 102.9838),
      aliases: ['Koh Kong', 'Kaoh Kong', 'Khemarak Phoumin'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងខេមរភូមិន្ទ',
          english: 'Krong Khemarak Phoumin',
          aliases: ['Khemarak Phoumin', 'Koh Kong'],
          sangkats: [
            SangkatOption(
              khmer: 'សង្កាត់ស្មាច់មានជ័យ',
              english: 'Smach Meanchey',
            ),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'kratie',
      khmer: 'ខេត្តក្រចេះ',
      english: 'Kratie',
      center: LatLng(12.4881, 106.0188),
      aliases: ['Kratie', 'Kracheh'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងក្រចេះ',
          english: 'Krong Kratie',
          aliases: ['Krong Kratie', 'Kratie'],
          sangkats: [SangkatOption(khmer: 'សង្កាត់ក្រចេះ', english: 'Kratie')],
        ),
      ],
    ),
    ProvinceOption(
      code: 'stung_treng',
      khmer: 'ខេត្តស្ទឹងត្រែង',
      english: 'Stung Treng',
      center: LatLng(13.5259, 105.9683),
      aliases: ['Stung Treng', 'Stueng Traeng'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងស្ទឹងត្រែង',
          english: 'Krong Stung Treng',
          aliases: ['Krong Stung Treng', 'Stung Treng'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ស្ទឹងត្រែង', english: 'Stung Treng'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'ratanakiri',
      khmer: 'ខេត្តរតនគិរី',
      english: 'Ratanakiri',
      center: LatLng(13.7394, 106.9873),
      aliases: ['Ratanakiri', 'Ratanak Kiri', 'Banlung'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងបានលុង',
          english: 'Krong Banlung',
          aliases: ['Banlung', 'Ratanakiri'],
          sangkats: [
            SangkatOption(khmer: 'សង្កាត់ឡាបានសៀក', english: 'Labansiek'),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'mondulkiri',
      khmer: 'ខេត្តមណ្ឌលគិរី',
      english: 'Mondulkiri',
      center: LatLng(12.4558, 107.1881),
      aliases: ['Mondulkiri', 'Mondul Kiri', 'Sen Monorom'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងសែនមនោរម្យ',
          english: 'Krong Sen Monorom',
          aliases: ['Sen Monorom', 'Mondulkiri'],
          sangkats: [
            SangkatOption(
              khmer: 'សង្កាត់ស្ពានមានជ័យ',
              english: 'Spean Meanchey',
            ),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'preah_vihear',
      khmer: 'ខេត្តព្រះវិហារ',
      english: 'Preah Vihear',
      center: LatLng(13.8073, 104.9805),
      aliases: ['Preah Vihear'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងព្រះវិហារ',
          english: 'Krong Preah Vihear',
          aliases: ['Krong Preah Vihear', 'Preah Vihear'],
          sangkats: [
            SangkatOption(
              khmer: 'សង្កាត់កំពង់ប្រណាក',
              english: 'Kampong Pranak',
            ),
          ],
        ),
      ],
    ),
    ProvinceOption(
      code: 'oddar_meanchey',
      khmer: 'ខេត្តឧត្តរមានជ័យ',
      english: 'Oddar Meanchey',
      center: LatLng(14.1818, 103.5176),
      aliases: ['Oddar Meanchey', 'Otdar Meanchey', 'Samraong'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងសំរោង',
          english: 'Krong Samraong',
          aliases: ['Samraong', 'Oddar Meanchey'],
          sangkats: [SangkatOption(khmer: 'សង្កាត់សំរោង', english: 'Samraong')],
        ),
      ],
    ),
    ProvinceOption(
      code: 'pailin',
      khmer: 'ខេត្តប៉ៃលិន',
      english: 'Pailin',
      center: LatLng(12.8490, 102.6093),
      aliases: ['Pailin'],
      districts: [
        KhanOption(
          khmer: 'ក្រុងប៉ៃលិន',
          english: 'Krong Pailin',
          aliases: ['Krong Pailin', 'Pailin'],
          sangkats: [SangkatOption(khmer: 'សង្កាត់ប៉ៃលិន', english: 'Pailin')],
        ),
      ],
    ),
  ];

  /// Backward-compatible accessor for Phnom Penh's 10 Khans.
  static List<KhanOption> get phnomPenhKhans => phnomPenh.districts;

  /// Quick preset pairs used in Edit Profile when Phnom Penh is active.
  static const List<(String khmer, String english)> profilePresets = [
    ('សង្កាត់ផ្សារថ្មី, ខណ្ឌដូនពេញ', 'Phsar Thmei, Daun Penh'),
    ('សង្កាត់បឹងកេងកង ១, ខណ្ឌបឹងកេងកង', 'BKK 1, Boeung Keng Kang'),
    ('សង្កាត់មិត្តភាព, ខណ្ឌ ៧ មករា', 'Mittapheap, 7 Makara'),
    ('សង្កាត់បឹងកក់ ១, ខណ្ឌទួលគោក', 'Boeung Kak 1, Toul Kork'),
    ('សង្កាត់ទួលទំពូង ២, ខណ្ឌចំការមន', 'Toul Tompoung, Chamkarmon'),
    ('សង្កាត់ទឹកថ្លា, ខណ្ឌសែនសុខ', 'Teuk Thla, Sen Sok'),
  ];

  /// Builds province-specific neighborhood preset chips for Edit Profile.
  static List<(String khmer, String english)> presetsForProvince(
    ProvinceOption province,
  ) {
    if (province.code == phnomPenhCode) return profilePresets;
    final items = <(String, String)>[];
    for (final district in province.districts) {
      if (district.sangkats.isEmpty) {
        items.add((
          '${district.khmer}, ${province.khmer}',
          '${district.english}, ${province.english}',
        ));
      } else {
        for (final sangkat in district.sangkats.take(3)) {
          items.add((
            '${sangkat.khmer}, ${district.khmer}, ${province.khmer}',
            '${sangkat.english}, ${district.english}, ${province.english}',
          ));
        }
      }
    }
    return items;
  }

  /// Looks up a [ProvinceOption] by canonical code (e.g. `'siem_reap'`).
  static ProvinceOption? findProvinceByCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final needle = code.trim().toLowerCase();
    for (final province in provinces) {
      if (province.code == needle) return province;
    }
    return null;
  }

  /// Looks up a [ProvinceOption] by English, Khmer, or OSM Nominatim alias name.
  static ProvinceOption? findProvinceByName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final needle = _compact(raw);
    for (final province in provinces) {
      final khCore = _compact(province.shortKhmer);
      final enCompact = _compact(province.english);
      if (needle == enCompact ||
          needle.contains(enCompact) ||
          needle.contains(_compact(province.khmer)) ||
          (khCore.isNotEmpty && needle.contains(khCore)) ||
          province.aliases.any((alias) {
            final a = _compact(alias);
            return a.isNotEmpty && (needle == a || needle.contains(a));
          })) {
        return province;
      }
    }
    return null;
  }

  /// Returns the closest of the 25 provinces to [point] (fast Haversine fallback).
  static ProvinceOption nearestProvinceForPoint(LatLng point) {
    var best = provinces.first;
    var bestMeters = _haversineMeters(point, best.center);
    for (final province in provinces.skip(1)) {
      final meters = _haversineMeters(point, province.center);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = province;
      }
    }
    return best;
  }

  /// Infers a [ProvinceOption] from location strings or GPS coordinates.
  static ProvinceOption inferProvince({
    String? provinceCode,
    String? khmerLocation,
    String? englishLocation,
    LatLng? coordinates,
  }) {
    final byCode = findProvinceByCode(provinceCode);
    if (byCode != null) return byCode;

    final byEnglish = findProvinceByName(englishLocation);
    if (byEnglish != null) return byEnglish;

    final byKhmer = findProvinceByName(khmerLocation);
    if (byKhmer != null) return byKhmer;

    // Check Phnom Penh Khans explicitly so legacy "Phsar Thmei, Daun Penh"
    // strings resolve to Phnom Penh without coordinates.
    if (findDistrictInProvince(phnomPenh, englishLocation) != null ||
        findDistrictInProvince(phnomPenh, khmerLocation) != null) {
      return phnomPenh;
    }

    if (coordinates != null) {
      return nearestProvinceForPoint(coordinates);
    }
    return phnomPenh;
  }

  /// Finds a district (`ខណ្ឌ / ក្រុង / ស្រុក`) inside [province].
  static KhanOption? findDistrictInProvince(
    ProvinceOption province,
    String? raw,
  ) {
    if (raw == null || raw.trim().isEmpty) return null;
    final needle = _compact(raw);
    for (final district in province.districts) {
      final aliases = [district.english, ...district.aliases];
      final khCore = _compact(
        district.khmer
            .replaceFirst('ខណ្ឌ', '')
            .replaceFirst('ក្រុង', '')
            .replaceFirst('ស្រុក', ''),
      );
      if (aliases.any((alias) {
            final a = _compact(alias);
            return a.isNotEmpty && (needle == a || needle.contains(a));
          }) ||
          needle.contains(_compact(district.khmer)) ||
          (khCore.isNotEmpty && needle.contains(khCore))) {
        return district;
      }
    }
    return null;
  }

  /// Finds a [KhanOption] across Phnom Penh first, then all other provinces.
  static KhanOption? findKhanByEnglish(String? englishName) {
    if (englishName == null || englishName.trim().isEmpty) return null;
    final inPp = findDistrictInProvince(phnomPenh, englishName);
    if (inPp != null) return inPp;
    for (final province in provinces.skip(1)) {
      final match = findDistrictInProvince(province, englishName);
      if (match != null) return match;
    }
    return null;
  }

  /// Finds a [SangkatOption] (`សង្កាត់ / ឃុំ`) inside [khan] by English or Khmer name.
  static SangkatOption? findSangkatInKhan(
    KhanOption khan,
    String? englishName,
  ) {
    if (englishName == null || englishName.trim().isEmpty) return null;
    final needle = _compact(englishName);
    for (final sangkat in khan.sangkats) {
      final enCompact = _compact(sangkat.english);
      final khCore = _compact(
        sangkat.khmer.replaceFirst('សង្កាត់', '').replaceFirst('ឃុំ', ''),
      );
      if (needle == enCompact ||
          needle.contains(enCompact) ||
          needle.contains(_compact(sangkat.khmer)) ||
          (khCore.isNotEmpty && needle.contains(khCore))) {
        return sangkat;
      }
    }
    return null;
  }

  /// Resolves the citizen's Home (Province, optional District, optional Commune)
  /// without falsely falling back to Daun Penh for provincial residents.
  static ({ProvinceOption province, KhanOption? khan, SangkatOption? sangkat})
  matchFromProfileArea({
    required String khmerArea,
    required String englishArea,
    String? provinceCode,
  }) {
    final explicitProvince =
        findProvinceByCode(provinceCode) ??
        findProvinceByName(englishArea) ??
        findProvinceByName(khmerArea);

    if (explicitProvince != null) {
      final district =
          findDistrictInProvince(explicitProvince, englishArea) ??
          findDistrictInProvince(explicitProvince, khmerArea);
      if (district != null) {
        final sangkat =
            findSangkatInKhan(district, englishArea) ??
            findSangkatInKhan(district, khmerArea);
        return (province: explicitProvince, khan: district, sangkat: sangkat);
      }
      // Check sangkat-only match inside the explicit province.
      for (final d in explicitProvince.districts) {
        final s =
            findSangkatInKhan(d, englishArea) ??
            findSangkatInKhan(d, khmerArea);
        if (s != null) {
          return (province: explicitProvince, khan: d, sangkat: s);
        }
      }
      return (province: explicitProvince, khan: null, sangkat: null);
    }

    // Search all provinces for district or sangkat match (legacy Phnom Penh profiles).
    for (final province in provinces) {
      final district =
          findDistrictInProvince(province, englishArea) ??
          findDistrictInProvince(province, khmerArea);
      if (district != null) {
        final sangkat =
            findSangkatInKhan(district, englishArea) ??
            findSangkatInKhan(district, khmerArea);
        return (province: province, khan: district, sangkat: sangkat);
      }
    }

    for (final province in provinces) {
      for (final district in province.districts) {
        final sangkat =
            findSangkatInKhan(district, englishArea) ??
            findSangkatInKhan(district, khmerArea);
        if (sangkat != null) {
          return (province: province, khan: district, sangkat: sangkat);
        }
      }
    }

    return (
      province: phnomPenh,
      khan: phnomPenh.districts.first,
      sangkat: phnomPenh.districts.first.sangkats.first,
    );
  }

  /// Formats a human-readable bilingual label for a selected Province, District,
  /// and optional Commune.
  static ({String khmer, String english}) formatSelection({
    ProvinceOption? province,
    KhanOption? khan,
    SangkatOption? sangkat,
  }) {
    if (province == null && khan == null) {
      return (
        khmer: 'ទូទាំងប្រទេសកម្ពុជា · ២៥ រាជធានី-ខេត្ត',
        english: 'All Cambodia · 25 Provinces',
      );
    }
    final activeProvince = province ?? phnomPenh;
    if (khan == null) {
      if (activeProvince.isCapital) {
        return (
          khmer: 'គ្រប់ខណ្ឌទាំងអស់ · រាជធានីភ្នំពេញ',
          english: 'All Districts · Phnom Penh',
        );
      }
      return (
        khmer: 'គ្រប់ស្រុក-ក្រុង · ${activeProvince.khmer}',
        english: 'All Districts · ${activeProvince.english}',
      );
    }
    if (sangkat == null) {
      if (activeProvince.isCapital) {
        return (khmer: khan.khmer, english: 'Khan ${khan.english}');
      }
      return (
        khmer: '${khan.khmer}, ${activeProvince.khmer}',
        english: '${khan.english}, ${activeProvince.english}',
      );
    }
    if (activeProvince.isCapital) {
      return (
        khmer: '${sangkat.khmer}, ${khan.khmer}',
        english: '${sangkat.english}, ${khan.english}',
      );
    }
    return (
      khmer: '${sangkat.khmer}, ${khan.khmer} · ${activeProvince.shortKhmer}',
      english: '${sangkat.english}, ${khan.english}, ${activeProvince.english}',
    );
  }

  /// Checks whether a report's structured province code & bilingual location
  /// strings match the selected [province], optional [khan], and optional [sangkat].
  static bool locationMatchesArea({
    required String khmerLocation,
    required String englishLocation,
    String? reportProvinceCode,
    ProvinceOption? province,
    KhanOption? khan,
    SangkatOption? sangkat,
  }) {
    if (province != null) {
      final resolvedCode =
          reportProvinceCode ??
          inferProvince(
            khmerLocation: khmerLocation,
            englishLocation: englishLocation,
          ).code;
      if (resolvedCode != province.code) return false;
    }

    if (khan == null) return true;

    final enCompact = _compact(englishLocation);
    final khCompact = _compact(khmerLocation);
    final khCore = _compact(
      khan.khmer
          .replaceFirst('ខណ្ឌ', '')
          .replaceFirst('ក្រុង', '')
          .replaceFirst('ស្រុក', ''),
    );
    final aliases = [khan.english, ...khan.aliases];

    final matchesKhan =
        aliases.any((alias) {
          final a = _compact(alias);
          return a.isNotEmpty && enCompact.contains(a);
        }) ||
        khCompact.contains(_compact(khan.khmer)) ||
        (khCore.isNotEmpty && khCompact.contains(khCore));
    if (!matchesKhan) return false;

    if (sangkat == null) return true;

    final sangkatKhCore = _compact(
      sangkat.khmer.replaceFirst('សង្កាត់', '').replaceFirst('ឃុំ', ''),
    );
    final sangkatEn = _compact(sangkat.english);
    return enCompact.contains(sangkatEn) ||
        khCompact.contains(_compact(sangkat.khmer)) ||
        (sangkatKhCore.isNotEmpty && khCompact.contains(sangkatKhCore));
  }

  static String _compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');

  static double _haversineMeters(LatLng a, LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
