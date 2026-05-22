---
name: create-app
description: 在 Hermes Mobile「应用 Tab」创建 static 静态页或 dynamic 动态（Node/Vue/React 构建产物）项目。用户开启「创建 App」模式时使用。
---

# Create App（Hermes Mobile 应用项目）

## 何时使用

用户要在 **Hermes Mobile App → 应用 Tab** 中打开你生成的页面/小应用，或明确说「创建 App / 做个网页 / 做个工具」。

## 项目根（唯一可写）

```
/data/hermes-projects/{slug}/
```

`slug`：小写 `[a-z0-9_-]`，与目录名、`project.json` 的 `id` 必须一致。

## 类型

| type | 说明 | 是否需要启动 |
|------|------|--------------|
| **static** | 纯 HTML/CSS/JS，文件在 `public/` | 否，Gateway 直接托管 |
| **dynamic** | 前后一体 Node 服务（含 Vue/React 构建后由 Node 托管，或 dev server） | 是，`POST /v1/projects/{slug}/start` |

## 目录规范

```
{slug}/
  project.json
  public/
    index.html
    assets/          # 可选
  server/              # 仅 dynamic
    package.json       # 可选
    index.mjs          # 监听 process.env.PORT
```

## project.json

### static 示例

```json
{
  "id": "hello",
  "title": "Hello 页",
  "type": "static",
  "version": "1.0.0",
  "frontend": { "entry": "public/index.html" }
}
```

### dynamic 示例

```json
{
  "id": "counter",
  "title": "计数器",
  "type": "dynamic",
  "version": "1.0.0",
  "backend": {
    "command": "node index.mjs",
    "cwd": "server",
    "healthPath": "/health"
  }
}
```

## dynamic 后端约定

1. **必须**监听 `process.env.PORT`（Gateway 注入，勿写死 3000）。
2. **必须**提供 `GET /health` → 200。
3. 业务 API 挂在 **`/api/*`**（Gateway 反代 `/v1/projects/{slug}/api/*` → `http://127.0.0.1:PORT/api/*`）。
4. 前端 fetch 推荐：`fetch('./api/xxx')` 或 `fetch('/v1/projects/{slug}/api/xxx')`（需 App WebView 带 JWT）。

### server/index.mjs 最小模板

```javascript
import http from 'node:http';
const port = Number(process.env.PORT || 4010);
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200); return res.end('ok');
  }
  if (req.url === '/api/ping') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ pong: true }));
  }
  res.writeHead(404); res.end('not found');
});
server.listen(port, '127.0.0.1');
```

## Vue / React

- **推荐**：本地 `npm run build`，把 `dist/` 内容复制到 `public/`，`type: static`。
- **需要服务端渲染或 API**：`type: dynamic`，`server/index.mjs` 用 `express` 静态托管 `../public` 并实现 `/api`。
- **dev server**：`type: dynamic`，`backend.command`: `npm run start`，`package.json` 的 start 必须 `--port $PORT` 或读 `process.env.PORT`。

## 交付给用户

1. 创建文件后说明 **slug、type、title**。
2. dynamic 提醒在 App **应用 Tab** 点「启动」，或你说明已调用 start API。
3. 给出打开链接：`{GATEWAY_PUBLIC_BASE_URL}/v1/projects/{slug}/`
4. 勿说「已发微信」；勿让用户离开 App 下载。

## Gateway 管理 API（JWT）

| 方法 | 路径 |
|------|------|
| GET | `/v1/projects` 列表 |
| GET | `/v1/projects/{slug}/meta` 详情 |
| POST | `/v1/projects/{slug}/start` |
| POST | `/v1/projects/{slug}/stop` |
| POST | `/v1/projects/{slug}/restart` |
| DELETE | `/v1/projects/{slug}?confirm=1` |

## 更新进行中（锁定）

当用户在 App 中打开某项目并请求修改时，Gateway 会 **锁定** 该项目直至本轮对话结束。
此时 App **应用 Tab** 会全屏 loading 并禁止操作；你只需改文件，完成后提示「已更新，将自动刷新」。

## 禁止

- 在 `/data/hermes-projects` 外写项目业务代码。
- dynamic 不写 `/health` 或固定端口。
- 仅口头说「做好了」而不给 slug 与链接。

## 委派 OpenCode / Claude Code / 其它编程工具

Gateway 的 create-app 规范**只注入主 Agent 的 system**；OpenCode、Claude Code、Cursor、Codex、Aider、子 Agent **不会自动继承**。

### 你必须做的

1. **每次委派前**，将 system 提示中的 **Delegation Brief 全文**（标记 `[Hermes Create-App Delegation Brief]`）粘贴到子工具 prompt / task / 首条指令。
2. 简报之后写具体任务（功能、UI、API）。
3. 子工具返回后，按简报末尾 **交付验收** 清单逐项检查；路径或 HermesApp 不合规则**你亲自改文件**。

### 委派 prompt 示例

```
你在 /data/hermes-projects/my-tool/ 下工作，禁止写到其它目录。

[粘贴 Delegation Brief 全文，含目录树、project.json 模板、HermesApp 禁止项]

任务：实现图片压缩器，大按钮选图，保存到相册 + 系统分享两个按钮。
```

修改已有项目时，Brief 中 slug 填具体值，`mode` 为 modify，**只能**改该 slug 目录。

### 交付验收（委派后自查）

- [ ] 所有文件位于 `{projectsRoot}/{slug}/` 下
- [ ] 存在 `project.json`，`id` 与 slug 一致
- [ ] 存在 `public/index.html`
- [ ] dynamic 有 `server/` + `GET /health` + `process.env.PORT`
- [ ] 前端用 HermesApp，无 drag-drop 唯一上传、无仅 `<a download>` 导出
- [ ] 未手写 `__HERMES_PROJECT__` / 未重复引入 host.js
- [ ] 告知用户 slug、type、链接 `{GATEWAY_PUBLIC_BASE_URL}/v1/projects/{slug}/`

辅助 API（JWT，**不能替代粘贴全文**）：`GET /v1/hermes-app/create-app-brief?slug={slug}`

## App WebView 宿主能力（HermesApp）— 必读

页面在 **Hermes Mobile App → 应用 Tab** 的 WebView 中运行。Gateway 会在 HTML 自动注入：

1. `window.__HERMES_PROJECT__`（`slug`、`apiBase`、`snippetsApi`）
2. `/v1/hermes-app/host.js` → 全局 **`window.HermesApp`**
3. **`window.__HERMES_APP_SNIPPETS__`** → 各 API **可复制代码示例**（含禁止项 antiPatterns）
4. HTML 注释 `<!— HermesApp 宿主 API —>` 速查

**编写 `public/index.html` 时：打开 Gateway 返回的 HTML 源码或读 `window.__HERMES_APP_SNIPPETS__`，复制对应 `snippets.*.code`，勿自创 drag-drop / file input 方案。**

**在 App 内**：`HermesApp.isAvailable === true`，必须用它完成选文件/保存/录音等原生交互。  
**在浏览器直连 Gateway**：`isAvailable === false`，可降级为大按钮 + 可选 `<input type="file">`，但 **禁止** 以 drag-drop 作为唯一上传方式。

### 强制规范（违反则 App 内不可用）

| 禁止 | 必须 |
|------|------|
| drag-drop / `dropzone` 作为唯一上传 | 复制 `snippets.pickImage.code` / `pickFile` |
| 仅 `<a download>` 导出 | `snippets.saveFile` + `snippets.shareFile`（分开两个按钮） |
| 假设 `getUserMedia` / `MediaRecorder` 在 WebView 可用 | `snippets.recordAudio.code` |
| 手写 `__HERMES_PROJECT__` 或重复 `<script src="host.js">` | 只用 Gateway 注入，业务 script 写 `</head>` 之后 |
| slug 当 JS 标识符（`image-compressor` 无引号） | 字符串 `"image-compressor"` 或 `HermesApp.getProject().slug` |
| 把超大 base64 塞进 chat | `uploadBlob` 或 `pickFile({ upload: true })` → 用返回的 `url` |

### 初始化（复制 `snippets.init.code`）

```javascript
await HermesApp.ready();
if (!HermesApp.isAvailable) {
  document.body.innerHTML = '<p style="padding:24px">请在 Hermes Mobile App 的「应用 Tab」中打开</p>';
  return;
}
const project = HermesApp.getProject(); // { slug, apiBase, hostApi }
```

### API 一览（均返回 Promise；完整示例见 `__HERMES_APP_SNIPPETS__`）

| 方法 | 说明 |
|------|------|
| `HermesApp.ready()` | 等待原生桥就绪 |
| `HermesApp.isAvailable` | 是否在 App WebView |
| `HermesApp.capabilities` | 能力表 `{ pickImage, recordAudio, ... }` |
| `HermesApp.getProject()` | 当前项目 meta |
| `pickImage({ source:'gallery'\|'camera', compress?, upload? })` | 选图；返回 `{ ok, base64, mimeType, filename, size, url?, uploadId? }` |
| `pickFile({ maxBytes?, upload?, allowedExtensions? })` | 选 PDF/CSV/音频/zip 等任意文件 |
| `pickVideo({ source, maxDurationSec?, upload? })` | 选视频 |
| `uploadBlob({ base64, filename, mimeType })` | 上传至 Gateway `/v1/upload`（≤8MB） |
| `compressImage({ base64, filename? })` | 客户端压图 |
| `saveFile({ base64?, url?, filename, mimeType?, picker? })` | **保存**（自动路由，见下表） |
| `shareFile({ base64?, url?, filename, mimeType?, title? })` | **分享任意文件**（系统分享面板） |
| `share({ text?, url?, title? })` | **分享文字/链接** |

**saveFile 自动路由**（`__HERMES_APP_SNIPPETS__.saveMatrix` / `HermesApp.getSaveDestinations()`）：

| 类型 | mime/扩展名 | 保存位置 |
|------|-------------|----------|
| 图片 | image/* | 相册 |
| 视频 | video/*, mp4/mov… | 相册 |
| 音频 | audio/*, mp3/m4a/wav… | Downloads |
| 文档 | pdf/doc/xls/ppt/epub… | Downloads |
| 压缩包 | zip/rar/7z… | Downloads |
| 文本 | txt/csv/json/html… | Downloads |
| 其它 | 任意 | Downloads |

可选 `picker: true` 或 `destination: 'picker'` 让用户自选保存位置。

| `toast(message)` | 顶部提示 |
| `clipboard.readText()` / `writeText({ text })` | 剪贴板 |
| `recordAudio.start({ maxDurationSec? })` | 开始录音 |
| `recordAudio.stop({ upload? })` | 停止并返回 `{ base64, mimeType: 'audio/mp4', ... }` |

失败时：`{ ok: false, code: 'CANCELLED'|'PERMISSION_DENIED'|'TOO_LARGE'|'UNAVAILABLE', message }` — **不要用 try/catch 代替 `if (!r.ok)`**。

### 图片压缩器（复制 `snippets.pickImage` + canvas，勿 drag-drop）

```javascript
document.getElementById('pickBtn').addEventListener('click', async function () {
  const r = await HermesApp.pickImage({ source: 'gallery', compress: false, upload: false });
  if (!r.ok) {
    if (r.code !== 'CANCELLED') await HermesApp.toast(r.message || '已取消');
    return;
  }
  const img = new Image();
  img.onload = function () {
    const canvas = document.createElement('canvas');
    const maxW = 1600;
    const ratio = Math.min(1, maxW / img.width);
    canvas.width = Math.round(img.width * ratio);
    canvas.height = Math.round(img.height * ratio);
    canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
    const dataUrl = canvas.toDataURL('image/jpeg', 0.8);
    // dataUrl.split(',')[1] 为 base64
    // 保存：HermesApp.saveFile({ base64, filename, mimeType: 'image/jpeg' })
    // 分享：HermesApp.shareFile({ base64, filename, mimeType, title: '…' })
  };
  img.src = 'data:' + r.mimeType + ';base64,' + r.base64;
});
```

参考实现：[`docs/hermes-projects/_examples/image-compressor/`](../../docs/hermes-projects/_examples/image-compressor/)

UI 要求：**大按钮、触控友好**；主操作区用 `min-height: 44px` 以上点击目标。

### 与业务 API 的关系

- 页面逻辑、AI 调用等仍可用 `fetch(project.apiBase + '/ping')` 或 `./api/...`（dynamic）。
- 二进制/媒体优先 HermesApp 选文件 → 需要公网 URL 时 `upload: true` → 把 `url` 传给后端 API。

### 修改已有项目时

若发现 `drag-drop`、`getUserMedia`、仅 `<a download>`，**必须一并重构**为 HermesApp API。
