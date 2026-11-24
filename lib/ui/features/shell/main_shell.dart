import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../../core/l10n.dart';
import '../../core/report_scope.dart';
import '../../core/theme.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/offline_sync_banner.dart';
import '../alerts/alerts_page.dart';
import '../home/home_page.dart';
import '../map/map_page.dart';
import '../profile/profile_page.dart';
import '../report/views/report_wizard_page.dart';

const double _wideLayoutBreakpoint = 600.0;

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;
  late final Set<int> _visitedTabs = {widget.initialIndex};

  void _selectTab(int value) {
    if (_index != value) HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visitedTabs.add(value);
    });
  }

  Future<void> _openReport({
    IssueCategory initialCategory = IssueCategory.pothole,
    ReportDraft? draft,
  }) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push<void>(
      SrolanhSlideUpRoute<void>(
        builder: (_) => ReportWizardPage(
          initialCategory: draft?.category ?? initialCategory,
          initialDraft: draft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ReportScope.of(context);
    final tr = Bilingual(repo.settings.englishFirst);
    final unreadCount = repo.unreadAlertCount;

    final pages = [
      HomePage(
        onReport: () => _openReport(),
        onSelectCategory: (cat) => _openReport(initialCategory: cat),
        onOpenMap: () => _selectTab(1),
        onResumeDraft: (draft) => _openReport(draft: draft),
      ),
      if (_visitedTabs.contains(1))
        MapPage(onBack: () => _selectTab(0))
      else
        const SizedBox.shrink(),
      const AlertsPage(),
      const ProfilePage(),
    ];

    Widget alertsIcon(bool selected) {
      final icon = Icon(
        selected ? Icons.notifications : Icons.notifications_outlined,
      );
      if (unreadCount <= 0) return icon;
      return Badge.count(
        count: unreadCount,
        backgroundColor: AppColors.saffron,
        textColor: AppColors.saffronInk,
        child: icon,
      );
    }

    final showBanner = OfflineSyncBanner.shouldShow(context);
    final statusBarStyle = !repo.isOnline
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget buildBodyStack() {
      return Column(
        children: [
          const OfflineSyncBanner(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: showBanner,
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedOpacity(
                      opacity: _index == i ? 1.0 : 0.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: pages[i],
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > _wideLayoutBreakpoint;

        if (isWide) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: statusBarStyle,
            child: Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _selectTab,
                    backgroundColor: Colors.white,
                    labelType: NavigationRailLabelType.all,
                    indicatorColor: AppColors.tealSoft,
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 16),
                      child: FloatingActionButton.small(
                        heroTag: 'rail-report',
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        tooltip: tr.primary('រាយការណ៍ថ្មី', 'New Report'),
                        onPressed: () => _openReport(),
                        child: const Icon(Icons.add),
                      ),
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: const Icon(
                          Icons.home,
                          color: AppColors.teal,
                        ),
                        label: Text(tr.primary('ទំព័រដើម', 'Home')),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.map_outlined),
                        selectedIcon: const Icon(
                          Icons.map,
                          color: AppColors.teal,
                        ),
                        label: Text(tr.primary('ផែនទី', 'Map')),
                      ),
                      NavigationRailDestination(
                        icon: alertsIcon(false),
                        selectedIcon: alertsIcon(true),
                        label: Text(tr.primary('ដំណឹង', 'Alerts')),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.person_outline),
                        selectedIcon: const Icon(
                          Icons.person,
                          color: AppColors.teal,
                        ),
                        label: Text(tr.primary('គណនី', 'Profile')),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: buildBodyStack()),
                ],
              ),
            ),
          );
        }

        // Mobile 5-slot bottom bar with floating center Mekong Teal '+' FAB
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: statusBarStyle,
          child: Scaffold(
            body: buildBodyStack(),
            bottomNavigationBar: _SrolanhBottomBar(
              selectedIndex: _index,
              unreadCount: unreadCount,
              tr: tr,
              onSelectTab: _selectTab,
              onTapReport: () => _openReport(),
            ),
          ),
        );
      },
    );
  }
}

class _SrolanhBottomBar extends StatelessWidget {
  const _SrolanhBottomBar({
    required this.selectedIndex,
    required this.unreadCount,
    required this.tr,
    required this.onSelectTab,
    required this.onTapReport,
  });

  final int selectedIndex;
  final int unreadCount;
  final Bilingual tr;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onTapReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Row(
            children: [
              _NavSlot(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: tr.primary('ទំព័រដើម', 'Home'),
                selected: selectedIndex == 0,
                tr: tr,
                onTap: () => onSelectTab(0),
              ),
              _NavSlot(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map_rounded,
                label: tr.primary('ផែនទី', 'Map'),
                selected: selectedIndex == 1,
                tr: tr,
                onTap: () => onSelectTab(1),
              ),
              Expanded(
                child: Center(
                  heightFactor: 1.0,
                  child: Tooltip(
                    message: tr.primary('រាយការណ៍បញ្ហា', 'Report issue'),
                    excludeFromSemantics: true,
                    child: Semantics(
                      button: true,
                      excludeSemantics: true,
                      label: tr.primary('រាយការណ៍បញ្ហា', 'Report issue'),
                      child: PressableScale(
                        child: InkWell(
                          key: const Key('center-report-fab'),
                          onTap: onTapReport,
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.teal,
                              shape: BoxShape.circle,
                              boxShadow: AppColors.fabShadow,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _NavSlot(
                icon: Icons.notifications_outlined,
                selectedIcon: Icons.notifications_rounded,
                label: tr.primary('ដំណឹង', 'Alerts'),
                selected: selectedIndex == 2,
                badgeCount: unreadCount,
                tr: tr,
                onTap: () => onSelectTab(2),
              ),
              _NavSlot(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: tr.primary('គណនី', 'Profile'),
                selected: selectedIndex == 3,
                tr: tr,
                onTap: () => onSelectTab(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.tr,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Bilingual tr;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.teal : AppColors.muted;
    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      color: color,
      size: 23,
    );
    if (badgeCount > 0) {
      iconWidget = Badge.count(
        count: badgeCount,
        backgroundColor: AppColors.saffron,
        textColor: AppColors.saffronInk,
        child: iconWidget,
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final semanticLabel = badgeCount > 0
        ? tr.primary(
            '$label ($badgeCount មិនទាន់អាន)',
            '$label ($badgeCount unread)',
          )
        : label;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        excludeSemantics: true,
        label: semanticLabel,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: selected ? 14 : 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.tealSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AnimatedScale(
                      scale: selected ? 1.06 : 1.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      child: iconWidget,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
