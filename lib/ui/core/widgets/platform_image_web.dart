import 'package:material_ui/material_ui.dart';

Widget buildLocalImageWidget({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  return Image.network(
    path,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}
