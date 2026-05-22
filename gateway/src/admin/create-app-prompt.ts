import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { getProjectsRoot, getPublicBaseUrlForProjects } from './projects-manager.js';
import {
  buildCreateAppDelegationBrief,
  buildCreateAppDelegationRulesMarkdown,
} from './create-app-delegation.js';
import { buildHermesAppSnippetsMarkdown, HERMES_APP_ANTI_PATTERNS } from './hermes-app-snippets.js';

const CREATE_APP_MARKER = '[Hermes Mobile Create App]';
const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

const MANDATORY_PREAMBLE = `${CREATE_APP_MARKER}

【强制 · create-app 技能】
你 **没有** 也不需要从 ~/.hermes/skills 自行加载技能；以下即为完整的 create-app SKILL 规范，**必须 100% 遵守**。
不要假设「用户已安装技能」或「稍后再读 SKILL.md」——现在就按下面规范用 file/terminal 工具创建或修改项目。

${buildCreateAppDelegationRulesMarkdown()}

`;

type SkillLoadResult = {
  body: string;
  source: 'file' | 'inline-fallback';
  path?: string;
};

let cachedBlock: string | null = null;
let cachedDiagnostics: SkillLoadResult | null = null;

function stripFrontmatter(raw: string): string {
  if (raw.startsWith('---')) {
    const end = raw.indexOf('---', 3);
    if (end > 0) return raw.slice(end + 3).trim();
  }
  return raw.trim();
}

function skillCandidatePaths(): string[] {
  const envPath = process.env.GATEWAY_CREATE_APP_SKILL_FILE?.trim();
  return [
    envPath,
    join(MODULE_DIR, '../../skills/create-app/SKILL.md'),
    join(process.cwd(), 'skills', 'create-app', 'SKILL.md'),
    join(process.cwd(), '..', 'docs', 'hermes-projects', 'skills', 'create-app', 'SKILL.md'),
  ].filter(Boolean) as string[];
}

function loadSkillFromDisk(): SkillLoadResult | null {
  for (const p of skillCandidatePaths()) {
    try {
      if (!existsSync(p)) continue;
      const raw = readFileSync(p, 'utf8');
      const body = stripFrontmatter(raw);
      if (body.length < 100) continue;
      return { body, source: 'file', path: p };
    } catch {
      /* try next */
    }
  }
  return null;
}

function inlineSkillFallback(projectsRoot: string, publicBase: string): SkillLoadResult {
  return {
    source: 'inline-fallback',
    body: `你处于 **「创建 App」模式**：用户要在 Hermes Mobile 的 **应用 Tab** 中使用你生成的页面/小应用。

## 项目根（唯一可写）

\`${projectsRoot}/{slug}/\`

## 类型

- **static**：仅 \`public/index.html\`，无需启动
- **dynamic**：\`server/index.mjs\` 监听 \`process.env.PORT\`，Gateway 反代 \`/v1/projects/{slug}/api/*\`

## 必需

\`project.json\` + \`public/index.html\`（dynamic 另需 server + GET /health）

## 交付

给出链接：${publicBase}/v1/projects/{slug}/

完整规范见 Gateway \`skills/create-app/SKILL.md\`。`,
  };
}

function resolveSkillContent(): SkillLoadResult {
  if (cachedDiagnostics) return cachedDiagnostics;
  const fromDisk = loadSkillFromDisk();
  if (fromDisk) {
    cachedDiagnostics = fromDisk;
    return fromDisk;
  }
  const projectsRoot = getProjectsRoot();
  const publicBase = getPublicBaseUrlForProjects();
  cachedDiagnostics = inlineSkillFallback(projectsRoot, publicBase);
  return cachedDiagnostics;
}

export function getCreateAppSkillDiagnostics(): {
  loaded: boolean;
  source: string;
  path: string | null;
  bodyLength: number;
} {
  const r = resolveSkillContent();
  return {
    loaded: r.body.length > 100,
    source: r.source,
    path: r.path ?? null,
    bodyLength: r.body.length,
  };
}

export function buildCreateAppPromptBlock(): string {
  if (cachedBlock) return cachedBlock;
  const projectsRoot = getProjectsRoot();
  const publicBase = getPublicBaseUrlForProjects();
  const skill = resolveSkillContent();
  const dynamicLines =
    skill.source === 'inline-fallback'
      ? `\n\n（警告：未读到磁盘 SKILL 文件，以下为精简 fallback；运维请检查 gateway/skills/create-app/SKILL.md）\n`
      : '';
  cachedBlock = `${MANDATORY_PREAMBLE}${dynamicLines}${skill.body}

${buildHermesAppSnippetsMarkdown()}

## 委派外部工具 — 复制此简报（每次委派 OpenCode / Claude Code / 子 Agent 必附）

${buildCreateAppDelegationBrief({
    projectsRoot,
    publicBase,
    mode: 'create',
    hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
  })}

---
运行时参数：项目根 \`${projectsRoot}\`，公网基址 \`${publicBase}\`
可选 API：\`GET /v1/hermes-app/create-app-brief?slug={slug}\`（JWT，辅助；仍以粘贴简报全文为主）`;
  return cachedBlock;
}

function contentToString(content: unknown): string {
  if (typeof content === 'string') return content;
  if (content == null) return '';
  return JSON.stringify(content);
}

function mergeCreateAppBlock(existing: unknown, block: string): string {
  const existingText = contentToString(existing).trim();
  if (!existingText) return block;
  if (existingText.includes(CREATE_APP_MARKER) && existingText.includes('project.json')) {
    return existingText;
  }
  if (existingText.includes(CREATE_APP_MARKER)) {
    return `${existingText}\n\n${block}`;
  }
  return `${existingText}\n\n${block}`;
}

/** 当 App 开启「创建 App」模式时注入完整 SKILL（仅 system，不改 user 正文）。 */
export function injectCreateAppSystemPrompt(messages: unknown[]): unknown[] {
  if (messages.length === 0) return messages;
  const block = buildCreateAppPromptBlock();
  const first = messages[0];
  if (first && typeof first === 'object' && (first as { role?: unknown }).role === 'system') {
    const m = first as { role: string; content: unknown };
    return [{ ...m, content: mergeCreateAppBlock(m.content, block) }, ...messages.slice(1)];
  }
  return [{ role: 'system', content: block }, ...messages.slice(1)];
}

const TARGET_PROJECT_MARKER = '[Hermes Mobile Target Project]';

/** 用户正在 App 中查看该项目，修改期间 Gateway 已锁定，勿让用户交互。 */
export function injectTargetProjectContext(messages: unknown[], slug: string): unknown[] {
  const projectsRoot = getProjectsRoot();
  const publicBase = getPublicBaseUrlForProjects();
  const block = `${TARGET_PROJECT_MARKER}

用户 **正在 App「应用 Tab」中打开项目 \`${slug}\`**，并请求你修改它。
Gateway 已 **锁定** 该项目直至本轮回复结束；App 会显示 loading 并禁止用户操作。

你必须：
- **仅**修改 \`${projectsRoot}/${slug}/\` 下文件（勿改其它 slug）。
- 在本轮内完成修改；完成后告知用户「已更新，应用将自动刷新」。
- **勿**让用户在更新过程中点击/操作该应用。
- 若需重启 dynamic 后端，说明完成后用户在 App 内刷新即可。
- 若页面仍使用 **drag-drop / getUserMedia / 仅 download 链接**，必须重构为 **HermesApp** API（见下方调用示例）。
- 编写 \`public/index.html\` 时 **复制** HermesApp 示例代码，勿自创上传/导出方案；Gateway 注入的页面含 \`window.__HERMES_APP_SNIPPETS__\`。
- **委派外部编程工具时**：必须附带下方 Delegation Brief 全文；即使委派，也**只能**改 \`${projectsRoot}/${slug}/\`。

${buildHermesAppSnippetsMarkdown()}

## 委派外部工具 — 复制此简报（修改本项目时必附）

${buildCreateAppDelegationBrief({
    projectsRoot,
    publicBase,
    slug,
    mode: 'modify',
    hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
  })}

打开链接：${publicBase}/v1/projects/${slug}/`;

  if (messages.length === 0) return [{ role: 'system', content: block }];
  const first = messages[0];
  if (first && typeof first === 'object' && (first as { role?: unknown }).role === 'system') {
    const m = first as { role: string; content: unknown };
    const existing = contentToString(m.content);
    if (existing.includes(TARGET_PROJECT_MARKER)) return messages;
    return [{ ...m, content: `${existing}\n\n${block}` }, ...messages.slice(1)];
  }
  return [{ role: 'system', content: block }, ...messages];
}

/** 启动时校验 SKILL 是否可读（写入日志，不阻断启动） */
export function logCreateAppSkillStatus(log: { warn: (o: unknown, msg?: string) => void; info: (o: unknown, msg?: string) => void }): void {
  const d = getCreateAppSkillDiagnostics();
  if (d.source === 'inline-fallback') {
    log.warn(d, 'create-app SKILL 未从磁盘加载，使用 fallback；请确认 gateway/skills 已 COPY 进镜像');
  } else {
    log.info(d, 'create-app SKILL 已加载');
  }
}
