import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/cambodia_locations.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/bilingual_text.dart';
import '../../core/widgets/user_avatar.dart';
import '../news/area_news_page.dart';
import 'edit_profile_page.dart';
import 'my_reports_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _callEmergencyHotline(BuildContext context, Bilingual tr) async {
    final uri = Uri(scheme: 'tel', path: '1190');
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr.primary(
                'សូមហៅទៅលេខបន្ទាន់ 1190 ដោយផ្ទាល់ពីទូរស័ព្ទអ្នក',
                'Dial road emergency hotline 1190 from your phone.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr.primary(
              'ខ្សែទូរស័ព្ទបន្ទាន់បញ្ហាផ្លូវ៖ 1190',
              'Road emergency hotline: 1190',
            ),
          ),
        ),
      );
    }
  }

  void _showPrivacyDialog(BuildContext context, Bilingual tr) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.shield_outlined,
          color: AppColors.teal,
          size: 32,
        ),
        title: Text(tr.primary('ឯកជនភាព និងសុវត្ថិភាព', 'Privacy-by-Design')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PrivacyPoint(
              icon: Icons.public_off_outlined,
              text: tr.primary(
                'ផែនទីសាធារណៈមិនបង្ហាញឈ្មោះ លេខទូរស័ព្ទ ឬលេខសម្គាល់អ្នករាយការណ៍ឡើយ។',
                'Public map pins never expose reporter name, phone, or user ID.',
              ),
            ),
            const SizedBox(height: 8),
            _PrivacyPoint(
              icon: Icons.photo_filter_outlined,
              text: tr.primary(
                'ទិន្នន័យ EXIF ក្នុងរូបថតត្រូវបានលុបចេញដោយស្វ័យប្រវត្តិមុនពេលរក្សាទុក។',
                'Camera EXIF metadata is stripped automatically on upload.',
              ),
            ),
            const SizedBox(height: 8),
            _PrivacyPoint(
              icon: Icons.lock_outline,
              text: tr.primary(
                'ព័ត៌មានគណនីត្រូវបានអ៊ិនគ្រីប TLS ទាំងពេលបញ្ជូន និងពេលរក្សាទុក។',
                'Phone numbers and credentials are encrypted in transit (TLS) and at rest.',
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr.primary('យល់ព្រម', 'Got it')),
          ),
        ],
      ),
    );
  }

  void _showHelpSheet(BuildContext context, Bilingual tr) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BilingualText(
                bilingual: tr,
                khmer: 'ជំនួយ និងទំនាក់ទំនងបន្ទាន់',
                english: 'Help & Emergency',
                fontSize: 18,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(Icons.phone_outlined, color: AppColors.teal),
                ),
                title: Text(
                  tr.primary('ខ្សែទូរស័ព្ទបន្ទាន់', 'Road Emergency Hotline'),
                ),
                subtitle: Text(
                  tr.primary(
                    'ក្រសួងសាធារណការ៖ 1190 (ចុចដើម្បីហៅ)',
                    'MPWT Road Hotline: 1190 (Tap to call)',
                  ),
                ),
                trailing: const Icon(
                  Icons.call_outlined,
                  color: AppColors.teal,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _callEmergencyHotline(context, tr);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.tealSoft,
                  child: Icon(Icons.chat_outlined, color: AppColors.teal),
                ),
                title: Text(tr.primary('ជំនួយកម្មវិធី', 'App Support')),
                subtitle: Text(
                  tr.primary(
                    'សួរសំណួរអំពីការរាយការណ៍ ឬតាមដានជួសជុល',
                    'Get help with reporting or repair tracking',
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr.primary(
                          'ក្រុមជំនួយ SrolanhCity ត្រៀមជួយ ២៤/៧',
                          'SrolanhCity citizen support is available 24/7.',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditProfile(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final settings = repo.settings;
    final profile = repo.profile;
    final tr = Bilingual(settings.englishFirst);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Citizen Avatar + Editable Identity Header
              Center(
                child: Semantics(
                  button: true,
                  label: tr.primary('កែប្រែព័ត៌មានគណនី', 'Edit profile'),
                  child: InkWell(
                    onTap: () => _openEditProfile(context),
                    customBorder: const CircleBorder(),
                    child: UserAvatar(
                      profile: profile,
                      radius: 40,
                      showEditBadge: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: BilingualText(
                  bilingual: tr,
                  khmer: profile.khmerName,
                  english: profile.maskedPhone.isEmpty
                      ? profile.englishName
                      : '${profile.englishName} · ${profile.maskedPhone}',
                  fontSize: 20,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  profile.hasHomeArea
                      ? tr.primary(
                          profile.khmerHomeArea,
                          profile.englishHomeArea,
                        )
                      : tr.primary(
                          'មិនទាន់កំណត់តំបន់រស់នៅ',
                          'Home area not set',
                        ),
                  key: profile.hasHomeArea
                      ? null
                      : const Key('profile-empty-area-hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontStyle: profile.hasHomeArea
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  key: const Key('edit-profile-btn'),
                  onPressed: () => _openEditProfile(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(
                    tr.paired('កែប្រែព័ត៌មាន', 'Edit profile'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 42),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Citizen Impact Strip
              Row(
                children: [
                  _ImpactMetricCard(
                    value: '${repo.myReports.length}',
                    label: tr.primary('របាយការណ៍ខ្ញុំ', 'My reports'),
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 8),
                  _ImpactMetricCard(
                    value: '${repo.totalCitizensHelped}',
                    label: tr.primary('អ្នករងផលប៉ះពាល់', 'Citizens helped'),
                    color: AppColors.priorityColor(4),
                  ),
                  const SizedBox(width: 8),
                  _ImpactMetricCard(
                    value: '${repo.myResolvedCount}',
                    label: tr.primary('ជួសជុលរួច', 'Verified fixes'),
                    color: AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Preferences Card
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.englishFirst,
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        repo.updateSettings(
                          settings.copyWith(englishFirst: value),
                        );
                      },
                      secondary: const Icon(
                        Icons.language,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary(
                          'ប្រើភាសាអង់គ្លេសជាមុន',
                          'Use English First',
                        ),
                      ),
                      subtitle: Text(
                        tr.primary(
                          'ប្តូរភាសាចម្បងនៃកម្មវិធីភ្លាមៗ',
                          'Switches primary app language immediately',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    SwitchListTile(
                      value: settings.notificationsEnabled,
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        repo.updateSettings(
                          settings.copyWith(notificationsEnabled: value),
                        );
                      },
                      secondary: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary('ការជូនដំណឹង', 'Repair Notifications'),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    SwitchListTile(
                      value: settings.anonymousByDefault,
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        repo.updateSettings(
                          settings.copyWith(anonymousByDefault: value),
                        );
                      },
                      secondary: const Icon(
                        Icons.visibility_off_outlined,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary(
                          'របាយការណ៍អនាមិកជាលំនាំដើម',
                          'Anonymous Mode by Default',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Citizen Links Card
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary(
                          'ព័ត៌មានផ្ទាល់ខ្លួន',
                          'Personal Information',
                        ),
                      ),
                      subtitle: Text(
                        tr.primary(
                          'ឈ្មោះ លេខទូរស័ព្ទ និងតំបន់រស់នៅ',
                          'Name, phone number & home district',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openEditProfile(context),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary('របាយការណ៍របស់ខ្ញុំ', 'My Reports'),
                      ),
                      trailing: Chip(
                        label: Text(
                          '${repo.myReports.length}',
                          style: AppFonts.displayStyle(
                            fontSize: 12,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const MyReportsPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Builder(
                      builder: (context) {
                        final area = repo.resolvedNewsArea;
                        final areaLabel =
                            CambodiaLocationCatalog.formatSelection(
                              province: area.province,
                              khan: area.khan,
                              sangkat: area.sangkat,
                            );
                        return ListTile(
                          leading: const Icon(
                            Icons.newspaper_outlined,
                            color: AppColors.teal,
                          ),
                          title: Text(tr.primary('ព័ត៌មានតំបន់', 'Area News')),
                          subtitle: Text(
                            tr.primary(areaLabel.khmer, areaLabel.english),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const AreaNewsPage(),
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    ListTile(
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary(
                          'ឯកជនភាព និងសុវត្ថិភាព',
                          'Privacy & Security',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPrivacyDialog(context, tr),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    ListTile(
                      leading: const Icon(
                        Icons.help_outline,
                        color: AppColors.teal,
                      ),
                      title: Text(
                        tr.primary(
                          'ជំនួយ និងខ្សែទូរស័ព្ទ 1190',
                          'Help & Hotline 1190',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showHelpSheet(context, tr),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImpactMetricCard extends StatelessWidget {
  const _ImpactMetricCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppFonts.displayStyle(fontSize: 19, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.teal),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
