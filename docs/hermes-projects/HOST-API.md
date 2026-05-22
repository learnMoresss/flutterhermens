# HermesApp Host API（App WebView 宿主能力）

Hermes Mobile **应用 Tab** 通过 WebView 加载 Gateway 托管的项目页面。桌面 Web 习惯（拖拽上传、`<a download>`、`getUserMedia`）在移动端 WebView **不可靠**，须使用 **`window.HermesApp`**。

## 注入方式

Gateway 在 HTML 响应中自动插入：

```html
<!-- HermesApp 宿主 API 速查 + 禁止项 -->
<script>window.__HERMES_PROJECT__={...};</script>
<script src="/v1/hermes-app/host.js"></script>
<script>window.__HERMES_APP_SNIPPETS__={ antiPatterns, folderAntiPatterns, delegationBrief, snippets: { init, pickImage, ... } };</script>
```

- SDK：`/v1/hermes-app/host.js`
- **调用示例（AI 复制用）**：页面内 `window.__HERMES_APP_SNIPPETS__` 或 `GET /v1/hermes-app/snippets.js`
- **委派简报（OpenCode / Claude Code）**：`__HERMES_APP_SNIPPETS__.delegationBrief` 或 `GET /v1/hermes-app/create-app-brief?slug=xxx`（JWT）
- 源码：[`gateway/src/admin/hermes-app-snippets.ts`](../../gateway/src/admin/hermes-app-snippets.ts)

## 环境检测

```javascript
await HermesApp.ready();
if (!HermesApp.isAvailable) {
  // 浏览器直连 Gateway：降级 UI，勿依赖 drag-drop
}
```

## API

详见 [`gateway/skills/create-app/SKILL.md`](../../gateway/skills/create-app/SKILL.md) 中 **「App WebView 宿主能力」** 章节（与 create_app_mode 注入内容同步）。

## Gateway 路由

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/v1/hermes-app/host.js` | Host SDK（无需 JWT，可缓存） |
| GET | `/v1/hermes-app/snippets.js` | 调用示例 + `delegationBrief`（`__HERMES_APP_SNIPPETS__`，AI 复制用） |
| GET | `/v1/hermes-app/create-app-brief?slug=` | create-app 委派简报 JSON（需 JWT） |

## 限制

- `/v1/upload` 单文件最大 **8MB**；更大文件需分片或仅存 url 引用
- 当前 Android 权限已声明；iOS 待工程补齐 Info.plist
- Bridge 方法白名单，不支持任意 URL scheme 打开
