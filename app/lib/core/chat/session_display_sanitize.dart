/// 清洗 Hermes Dashboard 会话 title/snippet 中的内部提示词。
bool isInternalPromptText(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;

  final lower = t.toLowerCase();
  if (t.startsWith('[IMPORTANT:')) return true;
  if (lower.contains('scheduled cron job')) return true;
  if (lower.contains('you are running as a scheduled')) return true;
  if (t.startsWith('[Hermes Mobile BFF]')) return true;
  if (t.startsWith('[Hermes Mobile')) return true;
  if (t.startsWith('DELIVER') && t.length > 80) return true;

  // 超长方括号指令块（多为 system/cron 注入）
  if (t.startsWith('[') && t.length > 120 && t.contains(':')) return true;

  return false;
}

String sanitizeSessionTitle(String raw, {required String sessionId}) {
  final t = raw.trim();
  if (t.isEmpty || isInternalPromptText(t)) {
    final shortId = sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId;
    return shortId.isEmpty ? '计划任务' : '计划任务 · $shortId';
  }
  return t;
}

String? sanitizeSessionSnippet(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty || isInternalPromptText(t)) return '计划任务执行';
  return t;
}

bool shouldHideHistoryMessage(String role, String content) {
  if (role != 'user') return false;
  return isInternalPromptText(content);
}
