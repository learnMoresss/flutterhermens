import 'package:flutter/material.dart';

import '../../../core/chat/slash_commands.dart';
import '../../../core/theme/app_colors.dart';

/// 输入 `/` 时弹出的斜杠命令选择面板（中文）
class SlashCommandPalette extends StatelessWidget {
  const SlashCommandPalette({
    required this.commands,
    required this.onSelect,
    super.key,
  });

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand> onSelect;

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 4,
      color: AppColors.white,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: commands.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.grayLight),
          itemBuilder: (context, index) {
            final cmd = commands[index];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(cmd.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
              subtitle: Text(
                cmd.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray),
              ),
              trailing: cmd.local
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.grayLight),
                      ),
                      child: Text(
                        slashCommandCategoryLabels[cmd.category] ?? '',
                        style: const TextStyle(fontSize: 10, color: AppColors.gray),
                      ),
                    )
                  : null,
              onTap: () => onSelect(cmd),
            );
          },
        ),
      ),
    );
  }
}
