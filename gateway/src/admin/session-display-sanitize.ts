/** 与 App 端 session_display_sanitize 对齐的会话展示清洗。 */

export function isInternalPromptText(text: string): boolean {
  const t = text.trim();
  if (!t) return false;
  const lower = t.toLowerCase();
  if (t.startsWith('[IMPORTANT:')) return true;
  if (lower.includes('scheduled cron job')) return true;
  if (lower.includes('you are running as a scheduled')) return true;
  if (t.startsWith('[Hermes Mobile BFF]')) return true;
  if (t.startsWith('[Hermes Mobile')) return true;
  if (t.startsWith('DELIVER') && t.length > 80) return true;
  if (t.startsWith('[') && t.length > 120 && t.includes(':')) return true;
  return false;
}

export function sanitizeSessionTitle(raw: string, sessionId: string): string {
  const t = raw.trim();
  if (!t || isInternalPromptText(t)) {
    const shortId = sessionId.length > 8 ? sessionId.slice(0, 8) : sessionId;
    return shortId ? `计划任务 · ${shortId}` : '计划任务';
  }
  return t;
}

export function sanitizeSessionSnippet(raw: string | undefined | null): string | undefined {
  if (raw == null) return undefined;
  const t = raw.trim();
  if (!t || isInternalPromptText(t)) return '计划任务执行';
  return t;
}

export function sanitizeSessionRecord(session: Record<string, unknown>): Record<string, unknown> {
  const id = String(session.id ?? session.session_id ?? session.sessionId ?? '');
  const titleRaw = session.title ?? session.name ?? session.preview;
  const rawTitle =
    titleRaw != null && String(titleRaw).trim() ? String(titleRaw) : `会话 ${id}`;
  return {
    ...session,
    title: sanitizeSessionTitle(rawTitle, id),
    preview: sanitizeSessionSnippet(session.preview as string | undefined) ?? session.preview,
    snippet: sanitizeSessionSnippet(session.snippet as string | undefined) ?? session.snippet,
  };
}

export function sanitizeSessionsPayload(data: unknown): unknown {
  if (Array.isArray(data)) {
    return data.map((item) =>
      item && typeof item === 'object'
        ? sanitizeSessionRecord(item as Record<string, unknown>)
        : item,
    );
  }
  if (data && typeof data === 'object') {
    const obj = data as Record<string, unknown>;
    if (Array.isArray(obj.sessions)) {
      return {
        ...obj,
        sessions: obj.sessions.map((item) =>
          item && typeof item === 'object'
            ? sanitizeSessionRecord(item as Record<string, unknown>)
            : item,
        ),
      };
    }
    if (Array.isArray(obj.results)) {
      return {
        ...obj,
        results: obj.results.map((item) =>
          item && typeof item === 'object'
            ? sanitizeSessionRecord(item as Record<string, unknown>)
            : item,
        ),
      };
    }
  }
  return data;
}
