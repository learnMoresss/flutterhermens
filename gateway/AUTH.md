# Gateway 登录与鉴权约定

Gateway 作为 BFF：**App 登录**由 Gateway 本地校验（`GATEWAY_AUTH_*`）并签发 JWT；**对话**代理 Hermes API Server（`:8642`）；**会话**代理 Hermes Dashboard REST（`:9119`，可选）。

## 环境变量

| 变量 | 含义 |
|------|------|
| `HERMES_API_ORIGIN` | Hermes API Server 根 URL（默认端口 **8642**）。支持 `auto` / `docker-host` / `docker-bridge` / 裸 IPv4 简写。 |
| `HERMES_API_SERVER_KEY` | 调用 API Server 的 Bearer（仅服务端，**不下发 App**） |
| `HERMES_DASHBOARD_ORIGIN` | Dashboard REST 根 URL（默认 **9119**，可选） |
| `HERMES_DASHBOARD_TOKEN` | Dashboard 启动日志中的 session token（可选；未配置时会话 API 返回 503） |
| `GATEWAY_AUTH_USER` | App 登录用户名（可选；未设置则仅校验密码） |
| `GATEWAY_AUTH_PASSWORD` | App 登录密码（必填，否则 `/v1/login` 返回 501） |
| `JWT_SECRET` | Gateway 签发移动端 JWT 的密钥（至少 8 字符） |

宿主机须在 `~/.hermes/.env` 启用 API Server（见 `scripts/enable-hermes-api-server.sh`）。Dashboard 需 `hermes dashboard` 运行并绑定可被容器访问的地址（Docker 场景常用 `0.0.0.0:9119` + `--insecure`）。

## 服务器 `.env` 的维护方式

1. 复制 [`scripts/gateway-deploy.env.example`](../scripts/gateway-deploy.env.example) 为 **`scripts/gateway-deploy.env.local`**（已 gitignore）。
2. 填写 `HERMES_API_ORIGIN`、`HERMES_API_SERVER_KEY`、`GATEWAY_AUTH_*` 等。
3. 运行 `scripts/deploy-gateway-windows.ps1`：会将 `gateway-deploy.env.local` 覆盖写入远端 `~/gateway/.env`。

修改后须**重启网关容器**。

## App 连接向导（无需 JWT）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/v1/setup/discover` | 探测 API Server / Dashboard 可达性、备份目录配置 |
| GET | `/health` | 网关与上游健康摘要 |

## 登录与受保护接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/login` | body `{ username, password }` → Gateway JWT |
| POST | `/v1/chat/completions` | OpenAI 兼容；SSE 透传 Hermes API Server |
| GET | `/v1/sessions` | 代理 Dashboard 会话列表（需 JWT + Dashboard token） |
| GET | `/v1/sessions/:id/messages` | 会话历史 |
| GET | `/v1/sessions/search?q=` | 全文搜索 |
| DELETE | `/v1/sessions/:id` | 删除会话 |

所有 `/v1/*`（除 login、setup/discover）需 Header：`Authorization: Bearer <Gateway JWT>`。

## Docker 管理（`/v1/admin/docker/*`）

鉴权：有效 Gateway JWT。网关容器须挂载 `/var/run/docker.sock` 并安装 docker CLI。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/v1/admin/docker/status` | Docker 是否可用 |
| GET | `/v1/admin/docker/containers` | 列出容器；query：`search`、`state`（running/stopped/paused/all）、`project` |
| GET | `/v1/admin/docker/containers/:id` | inspect 详情 |
| GET | `/v1/admin/docker/containers/:id/stats` | 资源占用（CPU/内存等） |
| GET | `/v1/admin/docker/containers/:id/logs?tail=200` | 容器日志（tail 1–2000） |
| POST | `/v1/admin/docker/containers/:id/start` | 启动 |
| POST | `/v1/admin/docker/containers/:id/stop` | 停止 |
| POST | `/v1/admin/docker/containers/:id/restart` | 重启 |
| POST | `/v1/admin/docker/containers/:id/pause` | 暂停 |
| POST | `/v1/admin/docker/containers/:id/unpause` | 继续 |
| POST | `/v1/admin/docker/containers/:id/rename` | body `{ name }` 重命名 |
| DELETE | `/v1/admin/docker/containers/:id` | 删除；query `force=true` 强制删除运行中容器 |
| GET | `/v1/admin/docker/images` | 镜像列表 |
| DELETE | `/v1/admin/docker/images/:id` | 删除镜像；query `force=true` |
| POST | `/v1/admin/docker/prune` | body `{ targets: ['containers','images'] }` 清理已停止容器/悬空镜像 |

## Hermes 应用项目（`/v1/projects/*`）

根目录：`GATEWAY_PROJECTS_ROOT`（默认 `/data/hermes-projects`）。类型：`static`（仅 public/）| `dynamic`（启动 server/ 子进程并反代 `/api`）。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/v1/projects` | 项目列表 |
| GET | `/v1/projects/:slug/meta` | 项目详情 |
| POST | `/v1/projects/:slug/start` | 启动 dynamic 后端 |
| POST | `/v1/projects/:slug/stop` | 停止 |
| POST | `/v1/projects/:slug/restart` | 重启 |
| DELETE | `/v1/projects/:slug?confirm=1` | 删除项目目录 |
| GET | `/v1/projects/:slug/` | WebView 加载前端（JWT） |
| ALL | `/v1/projects/:slug/api/*` | 反代到项目后端 |
| GET | `/v1/hermes-app/host.js` | App WebView Host SDK（无需 JWT） |
| GET | `/v1/hermes-app/snippets.js` | HermesApp 调用示例 + `delegationBrief`（无需 JWT） |
| GET | `/v1/hermes-app/create-app-brief?slug=` | create-app 委派简报 JSON（需 JWT；辅助，主 Agent 仍应粘贴全文给子工具） |

HTML 项目页自动注入 `__HERMES_PROJECT__` + `host.js` + `__HERMES_APP_SNIPPETS__`；页面内使用 `HermesApp.*` 调用原生选图/文件/录音/保存等能力。详见 `docs/hermes-projects/HOST-API.md`。

聊天 body 可选 `create_app_mode: true`，Gateway **强制**将完整 `gateway/skills/create-app/SKILL.md` 注入 **system**（不依赖 Hermes 自行加载 skills）。注入内容含 **Delegation Brief**：主 Agent 委派 OpenCode / Claude Code 等外部编程工具时，**必须**将简报全文粘贴到子工具 prompt。`/health` 返回 `createAppSkill` 诊断字段。

## Hermes 运维（`/v1/admin/hermes/*`）

鉴权：有效 Gateway JWT。详见 [`README.md`](README.md)。
