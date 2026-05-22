import 'package:flutter/material.dart';

import '../../../core/device_actions/device_action_model.dart';
import '../../../core/device_actions/device_action_registry.dart';
import '../../../core/theme/app_colors.dart';
import 'approval_action_bar.dart';

class DeviceActionCard extends StatelessWidget {
  const DeviceActionCard({
    required this.action,
    required this.onApprove,
    required this.onDeny,
    super.key,
  });

  final DeviceAction action;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final info = deviceActionTypeInfo(action.type);
    final preview = formatActionParamsPreview(action);
    final status = action.status;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grayLight),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(info.icon, size: 18, color: AppColors.black),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          if (action.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              action.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ],
          if (preview.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.gray,
                    height: 1.35,
                  ),
            ),
          ],
          if (action.errorMessage != null && action.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              action.errorMessage!,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
            ),
          ],
          if (status == DeviceActionStatus.pending &&
              onApprove != null &&
              onDeny != null) ...[
            ApprovalActionBar(onApprove: onApprove!, onDeny: onDeny!),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DeviceActionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      DeviceActionStatus.pending => ('待批准', AppColors.gray),
      DeviceActionStatus.approved => ('已批准', AppColors.black),
      DeviceActionStatus.denied => ('已拒绝', const Color(0xFFB00020)),
      DeviceActionStatus.executed => ('已完成', Colors.green.shade700),
      DeviceActionStatus.failed => ('失败', const Color(0xFFB00020)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
