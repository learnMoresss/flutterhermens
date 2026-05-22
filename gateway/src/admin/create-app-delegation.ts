export const CREATE_APP_DELEGATION_MARKER = '[Hermes Create-App Delegation Brief]';

export const CREATE_APP_FOLDER_ANTI_PATTERNS: string[] = [
  '禁止在 `{projectsRoot}/` 根目录直接写文件（必须 `{projectsRoot}/{slug}/`）',
  '禁止把 `index.html` 放在 slug 根目录（必须在 `public/index.html`）',
  '禁止在 slug 下建通用 Web 脚手架根（如 `src/`、`app/`、`pages/`）而不产出 `public/index.html` 入口',
  '禁止 Vue/React 只留 `npm run dev` 而不 `build` 到 `public/`（static 须可托管 HTML）',
  '禁止修改 gateway/、app/、docs/ 或 Hermes 主仓库代码来交付 App 项目',
  '禁止 slug 含大写、空格或特殊字符（仅 `[a-z0-9_-]`，与 `project.json.id` 一致）',
  '禁止 dynamic 后端写死端口 3000（必须 `process.env.PORT` + `GET /health`）',
];

export type CreateAppDelegationMode = 'create' | 'modify';

export type CreateAppDelegationBriefOptions = {
  projectsRoot: string;
  publicBase: string;
  slug?: string;
  mode?: CreateAppDelegationMode;
  /** 默认取 HermesApp 禁止项前 5 条；由 hermes-app-snippets 传入以保持单一数据源 */
  hermesAppAntiPatterns?: string[];
};

const STATIC_PROJECT_JSON = `{
  "id": "{slug}",
  "title": "应用标题",
  "type": "static",
  "version": "1.0.0",
  "frontend": { "entry": "public/index.html" }
}`;

const DYNAMIC_PROJECT_JSON = `{
  "id": "{slug}",
  "title": "应用标题",
  "type": "dynamic",
  "version": "1.0.0",
  "backend": {
    "command": "node index.mjs",
    "cwd": "server",
    "healthPath": "/health"
  }
}`;

export const CREATE_APP_DELIVERY_CHECKLIST: string[] = [
  '所有文件位于 `{projectsRoot}/{slug}/` 下，无越界路径',
  '存在 `project.json`，且 `id` 与目录 slug 一致',
  '存在 `public/index.html`（static 必需；dynamic 也应有前端入口）',
  'dynamic 有 `server/index.mjs`（或 project.json 指定 cwd），监听 `process.env.PORT`，提供 `GET /health`',
  '前端使用 HermesApp（`ready()` + `isAvailable` + pickImage/pickFile/saveFile/shareFile），无 drag-drop 唯一上传',
  '无 `<a download>` 作为唯一导出；保存与分享分开两个按钮',
  '未手写 `__HERMES_PROJECT__` / 未重复引入 `host.js`（Gateway 自动注入）',
  '交付给用户 slug、type、打开链接 `{publicBase}/v1/projects/{slug}/`',
];

function formatFolderAntiPatterns(projectsRoot: string, slug: string): string {
  return CREATE_APP_FOLDER_ANTI_PATTERNS.map((line) =>
    line.replaceAll('{projectsRoot}', projectsRoot).replaceAll('{slug}', slug),
  ).join('\n');
}

function formatChecklist(projectsRoot: string, publicBase: string, slug: string): string {
  return CREATE_APP_DELIVERY_CHECKLIST.map((line) =>
    line
      .replaceAll('{projectsRoot}', projectsRoot)
      .replaceAll('{publicBase}', publicBase)
      .replaceAll('{slug}', slug),
  )
    .map((line) => `- [ ] ${line}`)
    .join('\n');
}

export function buildCreateAppDelegationBrief(opts: CreateAppDelegationBriefOptions): string {
  const { projectsRoot, publicBase, mode = 'create' } = opts;
  const slug = opts.slug?.trim() || '{slug}';
  const slugHint =
    mode === 'modify'
      ? `**当前项目 slug**：\`${slug}\`（仅可修改此目录，禁止动其它 slug）`
      : `**新建 slug**：小写 \`[a-z0-9_-]\`，与目录名、project.json.id 一致（示例 \`my-tool\`）`;

  const hermesPatterns = opts.hermesAppAntiPatterns ?? [
    '禁止 drag-drop / dropzone 作为唯一上传方式（App WebView 不可用）',
    '禁止隐藏 <input type="file"> 作为 App 内主入口（Android WebView 点击常失效）',
    '禁止依赖 getUserMedia / MediaRecorder（WebView 权限不可靠）',
    '禁止仅用 <a download> 导出（须 HermesApp.saveFile / shareFile）',
    '禁止把 saveFile 当分享用：saveFile=保存到相册/下载目录，shareFile=系统分享面板',
  ];
  const hermesTop5 = hermesPatterns.slice(0, 5).map((s) => `- ${s}`).join('\n');

  return `${CREATE_APP_DELEGATION_MARKER}

## 工作区（唯一可写）

\`${projectsRoot}/${slug}/\`

${slugHint}

## 标准目录树

\`\`\`
${slug}/
  project.json
  public/
    index.html          # 必需
    assets/             # 可选 CSS/JS/图片
  server/               # 仅 type: dynamic
    index.mjs           # 监听 process.env.PORT
\`\`\`

## 目录禁止（违反即无效）

${formatFolderAntiPatterns(projectsRoot, slug)}

## project.json 模板

**static**（替换 \`{slug}\` 与 title）：

\`\`\`json
${STATIC_PROJECT_JSON.replaceAll('{slug}', slug)}
\`\`\`

**dynamic**：

\`\`\`json
${DYNAMIC_PROJECT_JSON.replaceAll('{slug}', slug)}
\`\`\`

## dynamic 后端约定

- 监听 \`process.env.PORT\`（Gateway 注入，勿写死 3000）
- \`GET /health\` → 200
- 业务 API 挂在 \`/api/*\`（Gateway 反代 \`/v1/projects/${slug}/api/*\`）
- 前端 fetch：\`./api/xxx\` 或 \`/v1/projects/${slug}/api/xxx\`

## HermesApp（App WebView 必读）

页面在 Hermes Mobile **应用 Tab** WebView 运行；Gateway 已注入 \`HermesApp\` 与 \`__HERMES_APP_SNIPPETS__\`。

**禁止（Top 5）**：
${hermesTop5}

**必须**：复制 \`snippets.init\`、\`pickImage\` / \`pickFile\`、\`saveFile\`、\`shareFile\` 示例代码；勿自创 drag-drop / file input 主入口。

## 交付验收（主 Agent / 子工具完成后自查）

${formatChecklist(projectsRoot, publicBase, slug)}

打开链接：${publicBase}/v1/projects/${slug}/`;
}

export function buildCreateAppDelegationRulesMarkdown(): string {
  return `## 委派 OpenCode / Claude Code / Cursor / 其它编程工具（违反即错误）

Gateway 的 create-app 规范**只注入主 Agent 的 system**；OpenCode、Claude Code、子 Agent、terminal 代写**不会自动继承**。

**触发**：用户要求用外部编程工具写代码、改项目、脚手架、npm init 等。

**你必须**：
1. 将下方 **Delegation Brief 全文**（含 \`${CREATE_APP_DELEGATION_MARKER}\`）粘贴到子工具 prompt / task / 首条指令
2. 在简报之后写具体任务（功能、UI、API）
3. 子工具返回后，按简报末尾 **交付验收** 清单逐项检查；不合格则你亲自改文件

**禁止**：
- 只传「帮我写个 xxx 工具」而不带路径与 HermesApp 约束
- 假设子工具「知道 Hermes 项目结构」
- 子工具写到 slug 外或 generic \`src/\` 结构后直接宣布完成`;
}
