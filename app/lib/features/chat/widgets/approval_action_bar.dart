import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 危险操作待审批时的批准/拒绝按钮
class ApprovalActionBar extends StatelessWidget {
  const ApprovalActionBar({
    required this.onApprove,
    required this.onDeny,
    super.key,
  });

  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('批准'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.black,
              side: const BorderSide(color: AppColors.black),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onDeny,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('拒绝'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB00020),
              side: const BorderSide(color: Color(0xFFB00020)),
            ),
          ),
        ],
      ),
    );
  }
}
