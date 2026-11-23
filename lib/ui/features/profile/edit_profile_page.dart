import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/cambodia_locations.dart';
import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/user_avatar.dart';

/// Allows citizens to edit their local profile information (name, phone,
/// home Sangkat/Khan, and avatar photo).
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _khmerNameController;
  late final TextEditingController _englishNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _khmerAreaController;
  late final TextEditingController _englishAreaController;

  ProvinceOption _selectedProvince = CambodiaLocationCatalog.phnomPenh;
  String? _avatarPhotoPath;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _khmerNameController = TextEditingController();
    _englishNameController = TextEditingController();
    _phoneController = TextEditingController();
    _khmerAreaController = TextEditingController();
    _englishAreaController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final profile = ReportScope.read(context).profile;
      _khmerNameController.text = profile.khmerName;
      _englishNameController.text = profile.englishName;
      _phoneController.text = profile.phoneNumber;
      _khmerAreaController.text = profile.khmerHomeArea;
      _englishAreaController.text = profile.englishHomeArea;
      _selectedProvince = CambodiaLocationCatalog.matchFromProfileArea(
        khmerArea: profile.khmerHomeArea,
        englishArea: profile.englishHomeArea,
        provinceCode: profile.homeProvinceCode,
      ).province;
      _avatarPhotoPath = profile.avatarPhotoPath;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _khmerNameController.dispose();
    _englishNameController.dispose();
    _phoneController.dispose();
    _khmerAreaController.dispose();
    _englishAreaController.dispose();
    super.dispose();
  }

  UserProfile _buildDraftProfile() => UserProfile(
    khmerName: _khmerNameController.text.trim().isEmpty
        ? 'សុវណ្ណារិទ្ធ'
        : _khmerNameController.text.trim(),
    englishName: _englishNameController.text.trim().isEmpty
        ? 'Sovannarith'
        : _englishNameController.text.trim(),
    phoneNumber: _phoneController.text.trim(),
    khmerHomeArea: _khmerAreaController.text.trim(),
    englishHomeArea: _englishAreaController.text.trim(),
    homeProvinceCode: _selectedProvince.code,
    avatarPhotoPath: _avatarPhotoPath,
  );

  Future<void> _openProvincePicker(Bilingual tr) async {
    var query = '';
    final picked = await showModalBottomSheet<ProvinceOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final needle = query.trim().toLowerCase();
          final matches = CambodiaLocationCatalog.provinces
              .where((p) {
                if (needle.isEmpty) return true;
                return p.english.toLowerCase().contains(needle) ||
                    p.khmer.toLowerCase().contains(needle) ||
                    p.aliases.any((a) => a.toLowerCase().contains(needle));
              })
              .toList(growable: false);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.78,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BilingualText(
                      bilingual: tr,
                      khmer: 'ជ្រើសរើសរាជធានី / ខេត្ត (២៥)',
                      english: 'Choose Capital / Province (25)',
                      fontSize: 17,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(
                        hintText: tr.primary(
                          'ស្វែងរកខេត្ត (ឧ. សៀមរាប, កំពត)...',
                          'Search province (e.g., Siem Reap, Kampot)...',
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, index) {
                          final province = matches[index];
                          final selected =
                              province.code == _selectedProvince.code;
                          return ListTile(
                            key: Key('edit-province-option-${province.code}'),
                            dense: true,
                            leading: Icon(
                              province.isCapital
                                  ? Icons.location_city_rounded
                                  : Icons.map_outlined,
                              color: selected
                                  ? AppColors.teal
                                  : AppColors.muted,
                              size: 20,
                            ),
                            title: Text(
                              tr.primary(province.khmer, province.english),
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppColors.tealDark
                                    : AppColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              tr.secondary(province.khmer, province.english),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.teal,
                                    size: 19,
                                  )
                                : null,
                            onTap: () => Navigator.pop(sheetCtx, province),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    final presets = CambodiaLocationCatalog.presetsForProvince(picked);
    setState(() {
      _selectedProvince = picked;
      if (presets.isNotEmpty) {
        _khmerAreaController.text = presets.first.$1;
        _englishAreaController.text = presets.first.$2;
      } else {
        _khmerAreaController.text = picked.khmer;
        _englishAreaController.text = picked.english;
      }
    });
  }

  Future<void> _pickAvatar(ImageSource source, Bilingual tr) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 600,
      );
      if (picked != null && mounted) {
        setState(() => _avatarPhotoPath = picked.path);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'មិនអាចជ្រើសរូបភាពគណនីបានទេ',
              'Unable to select profile photo.',
            ),
          ),
        ),
      );
    }
  }

  void _showAvatarSheet(Bilingual tr) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(
                    Icons.photo_camera_outlined,
                    color: AppColors.teal,
                  ),
                ),
                title: Text(tr.paired('ថតរូបថ្មី', 'Take Photo')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickAvatar(ImageSource.camera, tr);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.teal,
                  ),
                ),
                title: Text(
                  tr.paired('ជ្រើសពីវិចិត្រសាល', 'Choose from Gallery'),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickAvatar(ImageSource.gallery, tr);
                },
              ),
              if (_avatarPhotoPath != null)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.dangerSoft,
                    child: Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
                  title: Text(
                    tr.paired('លុបរូបភាពគណនី', 'Remove Photo'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(() => _avatarPhotoPath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _save(Bilingual tr) {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    final repo = ReportScope.read(context);
    repo.updateProfile(_buildDraftProfile());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr.primary(
            'បានរក្សាទុកព័ត៌មានគណនីរួចរាល់!',
            'Profile information saved!',
          ),
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: IconButton(
                            tooltip: tr.primary('ត្រឡប់', 'Back'),
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BilingualText(
                            bilingual: tr,
                            khmer: 'កែប្រែព័ត៌មានគណនី',
                            english: 'Edit profile',
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          Center(
                            child: Semantics(
                              button: true,
                              label: tr.primary(
                                'ប្តូររូបភាពគណនី',
                                'Change profile photo',
                              ),
                              child: InkWell(
                                onTap: () => _showAvatarSheet(tr),
                                customBorder: const CircleBorder(),
                                child: UserAvatar(
                                  profile: _buildDraftProfile(),
                                  radius: 46,
                                  showEditBadge: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: () => _showAvatarSheet(tr),
                              child: Text(
                                tr.paired('ប្តូររូបភាព', 'Change photo'),
                                style: const TextStyle(
                                  color: AppColors.teal,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('edit-khmer-name'),
                            controller: _khmerNameController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'ឈ្មោះជាភាសាខ្មែរ',
                                'Khmer name',
                              ),
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return tr.primary(
                                  'សូមបញ្ចូលឈ្មោះជាភាសាខ្មែរ',
                                  'Please enter your Khmer name',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('edit-english-name'),
                            controller: _englishNameController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'ឈ្មោះជាភាសាអង់គ្លេស',
                                'English name',
                              ),
                              prefixIcon: const Icon(Icons.badge_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return tr.primary(
                                  'សូមបញ្ចូលឈ្មោះជាភាសាអង់គ្លេស',
                                  'Please enter your English name',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('edit-phone'),
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'លេខទូរស័ព្ទ',
                                'Phone number',
                              ),
                              prefixIcon: const Icon(Icons.phone_outlined),
                              helperText: tr.primary(
                                'រក្សាទុកជាឯកជន — មិនបង្ហាញលើផែនទីសាធារណៈឡើយ',
                                'Kept private — never shown on the public map',
                              ),
                              helperStyle: const TextStyle(
                                height: 1.5,
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                              helperMaxLines: 2,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().length < 6) {
                                return tr.primary(
                                  'សូមបញ្ចូលលេខទូរស័ព្ទត្រឹមត្រូវ',
                                  'Please enter a valid phone number',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          BilingualText(
                            bilingual: tr,
                            khmer: 'រាជធានី / ខេត្ត និងតំបន់រស់នៅ',
                            english: 'Home province & district',
                            fontSize: 14,
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            key: const Key('edit-province-picker-btn'),
                            onTap: () => _openProvincePicker(tr),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.public_rounded,
                                    color: AppColors.teal,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr.primary(
                                            'រាជធានី / ខេត្ត',
                                            'Capital / Province',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          tr.primary(
                                            _selectedProvince.khmer,
                                            _selectedProvince.english,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.teal,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (kh, en)
                                  in CambodiaLocationCatalog.presetsForProvince(
                                    _selectedProvince,
                                  ))
                                ChoiceChip(
                                  label: Text(tr.primary(kh, en)),
                                  selected: _englishAreaController.text == en,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _khmerAreaController.text = kh;
                                      _englishAreaController.text = en;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('edit-khmer-area'),
                            controller: _khmerAreaController,
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'សង្កាត់/ឃុំ និង ខណ្ឌ/ក្រុង/ស្រុក (ខ្មែរ)',
                                'Commune / District (Khmer)',
                              ),
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('edit-english-area'),
                            controller: _englishAreaController,
                            decoration: InputDecoration(
                              labelText: tr.paired(
                                'សង្កាត់/ឃុំ និង ខណ្ឌ/ក្រុង/ស្រុក (អង់គ្លេស)',
                                'Commune / District (English)',
                              ),
                              prefixIcon: const Icon(Icons.map_outlined),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    decoration: const BoxDecoration(
                      color: AppColors.paper,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        key: const Key('save-profile-btn'),
                        onPressed: () => _save(tr),
                        child: Text(
                          tr.paired('រក្សាទុកការផ្លាស់ប្តូរ', 'Save changes'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
