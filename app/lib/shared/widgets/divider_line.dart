import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class DividerLine extends StatelessWidget {
  const DividerLine({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: const Divider(height: 1, thickness: 1, color: AppColors.grayLight),
    );
  }
}
