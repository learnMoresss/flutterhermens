import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/app_scaffold.dart';

class AgentHubPage extends StatelessWidget {
  const AgentHubPage({super.key});

  static const _items = [
    _HubItem('模型', '查看已保存的模型预设', Icons.layers_outlined, 'models'),
    _HubItem('提供商', 'API 密钥与当前模型配置', Icons.key_outlined, 'providers'),
    _HubItem('工具集', '开关 Agent 可用工具能力', Icons.build_outlined, 'toolsets'),
    _HubItem('技能', '已安装的技能列表', Icons.auto_awesome_outlined, 'skills'),
    _HubItem('人格', '编辑 SOUL.md 人格设定', Icons.psychology_outlined, 'soul'),
    _HubItem('档案', '切换 Agent 配置档案', Icons.folder_copy_outlined, 'profiles'),
    _HubItem('记忆', 'Agent 长期记忆与用户档案', Icons.psychology_alt_outlined, 'memory'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Agent 管理',
      showDivider: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/home/workspace?tab=0'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            '管理远端 Hermes Agent 的模型、工具、技能与人格等配置。修改后部分设置需重启 Agent 或发送 /reload 生效。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, height: 1.45),
          ),
          const SizedBox(height: 16),
          ..._items.map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: AppColors.grayLight),
              ),
              child: ListTile(
                leading: Icon(item.icon),
                title: Text(item.title),
                subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/home/workspace/agent/${item.route}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubItem {
  const _HubItem(this.title, this.subtitle, this.icon, this.route);
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}
