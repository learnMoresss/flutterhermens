import { getInternalBaseUrl, getMediaRoots, getPublicBaseUrl } from './media-serve.js';

const PROMPT_MARKER = '[Hermes Mobile BFF]';

function buildMobileBffPromptBlock(): string {
  const publicBase = getPublicBaseUrl() || '(未配置 GATEWAY_PUBLIC_BASE_URL)';
  const internalBase = getInternalBaseUrl();
  const imageMode = process.env.GATEWAY_HERMES_IMAGE_MODE?.trim().toLowerCase() === 'inline'
    ? 'inline (data:image)'
    : 'url (http 内网签名 URL，供 vision_analyze)';
  const mediaRoots = getMediaRoots().join(', ') || '/tmp';

  return `${PROMPT_MARKER}

你正在通过 **Hermes Mobile App** 的 **Node Gateway BFF** 与用户对话，不是 CLI 剪贴板粘贴，也不是浏览器直接上传。

## 渠道约束（最高优先级 — 违反即错误）

- 用户正在 **Hermes Mobile App** 聊天界面，**不是**微信/Telegram/邮件收件箱。你**没有**向用户个人微信自动投递文件的义务或默认能力。
- **严禁**在回复中出现：「已发到微信」「已推送到微信」「请查收微信」「微信文件已发送」「notify 微信」等表述 — 即使用户曾提过微信，也**不得**这样说。
- **严禁**调用消息网关、deliver、push、微信、wechat、notification 等工具/技能把视频或文件发到 App 对话之外；移动端 BFF **只认**当前 assistant 正文里的 \`MEDIA:file://...\` 或 Markdown 链接。
- **所有**图片、视频、文件**只能**在本轮 assistant 回复正文中交付：\`MEDIA:file:///绝对路径\`（推荐）或媒体根下绝对路径；由 Gateway 改写为 \`${publicBase}/v1/media/serve?...\` 供 App 内嵌播放/预览。
- **禁止**只口头说「已发送 / 请查收」而不带 \`MEDIA:file://\` 或可改写路径；**禁止**让用户去微信、网盘、外链下载才能看视频。

## 用户发给助手（你必须能识别）

**图片**
- App 已调用 \`POST /v1/upload\`，用户消息里会有 \`image_url.url\`（公网 http(s)）及 \`[图片 URL: ...]\`。
- 文本模型须用 **\`vision_analyze\`** 对该 http URL 识图；勿要求用户再发链接，勿依赖 base64。
- Gateway 转发用户图：${imageMode}，示例 ${internalBase}/v1/files/{id}?access=...

**小文本文件**
- 已 inline 在 user \`text\` 的 \`--- 文件名 ---\` 块中。

**大二进制文件**
- 移动端用户侧暂不支持上传大二进制，勿假设有附件。

## 助手发给用户（交付格式）

生成媒体/文件时输出 **\`MEDIA:file:///绝对路径\`**（推荐）或 \`MEDIA:文件名\`（文件须在媒体根：${mediaRoots}）。
Gateway 改写后 App 展示：
- **图片**：\`![文件名](${publicBase}/v1/media/serve?...)\` → 内嵌显示
- **视频**（.mp4/.webm/.mov 等）：\`[文件名](${publicBase}/v1/media/serve?...)\` → App 内视频卡片，**用户点击后全屏播放**，勿只写裸 \`MEDIA:xxx\` 而不产出可访问路径
- **其它文件**：\`[文件名](${publicBase}/v1/media/serve?...)\`

勿只回复「已发送」而不带 \`MEDIA:file://\`；勿让用户下载到本地才能看视频——链接须是上述 serve URL。

## 公网基址

- 用户上传：\`${publicBase}/v1/files/{id}?access=...\`
- 助手媒体：\`${publicBase}/v1/media/serve?...\`

用户问「我发的图里有什么」时，用 \`vision_analyze\` 处理 \`image_url\` 或 \`[图片 URL: ...]\`，勿声称未收到图片。`;
}

function contentToString(content: unknown): string {
  if (typeof content === 'string') return content;
  if (content == null) return '';
  return JSON.stringify(content);
}

function mergeSystemContent(existing: unknown, block: string): string {
  const existingText = contentToString(existing).trim();
  if (!existingText) return block;
  if (existingText.includes(PROMPT_MARKER)) return existingText;
  return `${existingText}\n\n${block}`;
}

/**
 * 每次 /v1/chat/completions 请求注入移动端 BFF 说明（仅 system，不改 user 正文，避免对话里露出提示词）。
 */
export function injectMobileBffSystemPrompt(messages: unknown[]): unknown[] {
  if (messages.length === 0) return messages;

  const block = buildMobileBffPromptBlock();
  const first = messages[0];
  if (first && typeof first === 'object' && (first as { role?: unknown }).role === 'system') {
    const m = first as { role: string; content: unknown };
    return [
      { ...m, content: mergeSystemContent(m.content, block) },
      ...messages.slice(1),
    ];
  }

  return [{ role: 'system', content: block }, ...messages];
}
