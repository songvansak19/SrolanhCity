import 'package:material_ui/material_ui.dart';

import '../../../domain/models/report_models.dart';
import '../theme.dart';
import 'platform_image.dart';

/// Renders the citizen's avatar photo (if set) or crisp Mekong Teal initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    this.radius = 22,
    this.showEditBadge = false,
  });

  final UserProfile profile;
  final double radius;
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final path = profile.avatarPhotoPath;
    Widget avatar;
    if (path != null && path.isNotEmpty) {
      avatar = ClipOval(
        child: buildLocalImageWidget(
          path: path,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialsCircle(),
        ),
      );
    } else {
      avatar = _initialsCircle();
    }

    if (!showEditBadge) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.teal,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _initialsCircle() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.tealSoft,
      child: Text(
        profile.initials,
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.teal,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.62,
        ),
      ),
    );
  }
}
