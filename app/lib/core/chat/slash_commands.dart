/// Hermes 斜杠命令（参考 hermes-desktop，文案中文化）
enum SlashCommandCategory { chat, agent, tools, info }

class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.category,
    this.local = false,
  });

  final String name;
  final String description;
  final SlashCommandCategory category;
  final bool local;
}

const slashCommandCategoryLabels = {
  SlashCommandCategory.chat: '对话',
  SlashCommandCategory.agent: '智能体',
  SlashCommandCategory.tools: '工具',
  SlashCommandCategory.info: '信息',
};

const List<SlashCommand> allSlashCommands = [
  SlashCommand(name: '/new', description: '开始新对话', category: SlashCommandCategory.chat, local: true),
  SlashCommand(name: '/clear', description: '清空当前对话记录', category: SlashCommandCategory.chat, local: true),
  SlashCommand(name: '/btw', description: '旁路提问，不影响上下文', category: SlashCommandCategory.agent),
  SlashCommand(name: '/approve', description: '批准待确认操作', category: SlashCommandCategory.agent),
  SlashCommand(name: '/deny', description: '拒绝待确认操作', category: SlashCommandCategory.agent),
  SlashCommand(name: '/status', description: '查看智能体状态', category: SlashCommandCategory.agent),
  SlashCommand(name: '/reset', description: '重置对话上下文', category: SlashCommandCategory.agent),
  SlashCommand(name: '/compact', description: '压缩并摘要对话', category: SlashCommandCategory.agent),
  SlashCommand(name: '/undo', description: '撤销上一步操作', category: SlashCommandCategory.agent),
  SlashCommand(name: '/retry', description: '重试上次失败操作', category: SlashCommandCategory.agent),
  SlashCommand(name: '/fast', description: '切换优先处理（低延迟）', category: SlashCommandCategory.agent, local: true),
  SlashCommand(name: '/compress', description: '压缩对话（可指定主题）', category: SlashCommandCategory.agent),
  SlashCommand(name: '/usage', description: '查看 Token 用量与费用', category: SlashCommandCategory.agent, local: true),
  SlashCommand(name: '/debug', description: '显示诊断与调试信息', category: SlashCommandCategory.agent),
  SlashCommand(name: '/goal', description: '锁定跨轮次目标', category: SlashCommandCategory.agent),
  SlashCommand(name: '/steer', description: '引导进行中的智能体', category: SlashCommandCategory.agent),
  SlashCommand(name: '/queue', description: '排队后续任务', category: SlashCommandCategory.agent),
  SlashCommand(name: '/update', description: '更新 Hermes 到最新版', category: SlashCommandCategory.agent),
  SlashCommand(name: '/yolo', description: '自动批准所有操作', category: SlashCommandCategory.agent),
  SlashCommand(name: '/reload', description: '重载配置', category: SlashCommandCategory.agent),
  SlashCommand(name: '/stop', description: '停止当前任务', category: SlashCommandCategory.agent),
  SlashCommand(name: '/web', description: '搜索网页', category: SlashCommandCategory.tools),
  SlashCommand(name: '/image', description: '生成图片', category: SlashCommandCategory.tools),
  SlashCommand(name: '/browse', description: '浏览指定 URL', category: SlashCommandCategory.tools),
  SlashCommand(name: '/code', description: '编写或执行代码', category: SlashCommandCategory.tools),
  SlashCommand(name: '/file', description: '读写文件', category: SlashCommandCategory.tools),
  SlashCommand(name: '/shell', description: '运行 Shell 命令', category: SlashCommandCategory.tools),
  SlashCommand(name: '/help', description: '显示可用命令', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/tools', description: '列出可用工具', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/skills', description: '列出已安装技能', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/reload-skills', description: '重载技能目录', category: SlashCommandCategory.info),
  SlashCommand(name: '/model', description: '查看或切换模型', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/memory', description: '查看智能体记忆', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/persona', description: '查看当前人格设定', category: SlashCommandCategory.info, local: true),
  SlashCommand(name: '/version', description: '显示 Hermes 版本', category: SlashCommandCategory.info, local: true),
];

SlashCommand? matchSlashCommand(String input) {
  final trimmed = input.trim();
  if (!trimmed.startsWith('/')) return null;
  final token = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
  for (final cmd in allSlashCommands) {
    if (cmd.name.toLowerCase() == token) return cmd;
  }
  return null;
}

List<SlashCommand> filterSlashCommands(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || q == '/') return allSlashCommands;
  return allSlashCommands.where((c) => c.name.toLowerCase().startsWith(q)).toList(growable: false);
}
