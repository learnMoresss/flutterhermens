/// Hermes 快捷指令 chip 定义
class ChatShortcut {
  const ChatShortcut({
    required this.label,
    this.insertText,
    this.action,
  });

  final String label;
  final String? insertText;
  final ChatShortcutAction? action;
}

enum ChatShortcutAction { newChat, createAppMode }

const List<ChatShortcut> defaultChatShortcuts = [
  ChatShortcut(label: '创建 App', action: ChatShortcutAction.createAppMode),
  ChatShortcut(label: '自动执行', insertText: '/yolo'),
  ChatShortcut(label: '重载配置', insertText: '/reload'),
  ChatShortcut(label: '新对话', action: ChatShortcutAction.newChat),
  ChatShortcut(label: '停止', insertText: '/stop'),
];

/// UI 欢迎语，不参与 API 上下文
const chatWelcomeText =
    '你好，我是 Hermes 移动端。\n左侧可查看历史会话；发送消息将经 Gateway 连接 Hermes Agent。';

const chatNewChatText = '已开始新对话。发送第一条消息后 Hermes 将创建会话。';

bool isUiOnlyAssistantText(String text) {
  final t = text.trim();
  return t == chatWelcomeText ||
      t == chatNewChatText ||
      t == '…' ||
      t == '（空响应）' ||
      t.startsWith('已开始新对话') ||
      t.startsWith('对话已清空') ||
      t.startsWith('你好，我是 Hermes 移动端');
}
