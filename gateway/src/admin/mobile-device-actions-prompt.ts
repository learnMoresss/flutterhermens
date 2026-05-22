const DEVICE_ACTION_MARKER = '[Hermes Mobile Device Actions]';

function buildMobileDeviceActionsPromptBlock(): string {
  return `${DEVICE_ACTION_MARKER}

用户正在 **Hermes Mobile App** 聊天中。你可以提议**手机本地操作**（日历、提醒、分享等），但必须用下方 JSON 卡片格式；**禁止**口头声称「已设好闹钟/已加入日历」而不输出卡片。

## 输出格式（必须）

每个待用户批准的操作单独一个 fenced block（不要用普通 Markdown 列表代替）：

\`\`\`hermes-device-action
{
  "id": "act_unique_id",
  "type": "<见下表>",
  "title": "卡片标题（短）",
  "summary": "给用户看的说明",
  "params": { }
}
\`\`\`

- 同一回复可含多个 block；每个 block 一张卡片，用户需点「批准」后 App 才执行。
- \`id\` 在同一回复内唯一；\`params\` 字段必须符合 type 要求。
- 未获批准前不得写「已完成/已设置/请查收」。

## 支持的 type（v1）

| type | 用途 | params |
|------|------|--------|
| \`notification.schedule\` | 本地通知/提醒（类闹钟） | \`title\`, \`body\`, \`scheduledAt\`（ISO8601，含时区）；可选 \`repeatDaily\`: true |
| \`calendar.event\` | 写入系统日历 | \`title\`, \`startAt\`, \`endAt\`（ISO8601）；可选 \`location\`, \`description\`, \`reminderMinutes\`: [15, 60] |
| \`calendar.prefill\` | 打开系统日历预填（用户最终在系统 UI 保存） | 同 calendar.event |
| \`share.text\` | 系统分享 | \`text\`；可选 \`subject\` |
| \`clipboard.write\` | 复制到剪贴板 | \`text\` |
| \`settings.open\` | 打开系统设置 | \`target\`: \`notification\` / \`calendar\` / \`app\` |

## 示例

用户：「明天早上 9 点提醒我交报告」

\`\`\`hermes-device-action
{
  "id": "act_remind_report",
  "type": "notification.schedule",
  "title": "创建提醒",
  "summary": "明天 09:00 提醒交报告",
  "params": {
    "title": "交报告",
    "body": "别忘了提交报告",
    "scheduledAt": "2026-05-21T09:00:00+08:00"
  }
}
\`\`\`

## 禁止

- 不要用 \`/approve\` 文案代替设备卡片（那是服务端 Hermes 工具审批，与手机本地操作不同）。
- 不要输出用户无法理解的裸 JSON（必须包在 \`\`\`hermes-device-action 内）。
- \`home_widget\` 桌面小组件尚未开放，勿使用。`;
}

function contentToString(content: unknown): string {
  if (typeof content === 'string') return content;
  if (content == null) return '';
  return JSON.stringify(content);
}

function mergeSystemContent(existing: unknown, block: string): string {
  const existingText = contentToString(existing).trim();
  if (!existingText) return block;
  if (existingText.includes(DEVICE_ACTION_MARKER)) return existingText;
  return `${existingText}\n\n${block}`;
}

/** 注入移动端设备操作卡片规范（仅 system）。 */
export function injectMobileDeviceActionsPrompt(messages: unknown[]): unknown[] {
  if (messages.length === 0) return messages;

  const block = buildMobileDeviceActionsPromptBlock();
  const first = messages[0];
  if (first && typeof first === 'object' && (first as { role?: unknown }).role === 'system') {
    const m = first as { role: string; content: unknown };
    return [{ ...m, content: mergeSystemContent(m.content, block) }, ...messages.slice(1)];
  }

  return [{ role: 'system', content: block }, ...messages];
}
