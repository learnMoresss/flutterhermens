# Hermes Mobile（Flutter + Gateway BFF）

将 [Hermes](https://github.com/NousResearch/hermes) 能力移动端化的 **Flutter 薄壳客户端** + **Node Gateway 中转层（BFF）**  monorepo。

**Android 安装包** → [GitHub Releases 下载 APK](https://github.com/learnMoresss/flutterhermens/releases/latest)（无需克隆仓库、无需 Flutter 环境）

```text
Flutter App  →  Node Gateway (BFF)  →  Hermes API Server / Dashboard
     │                    │
     │                    └── 应用项目托管、媒体改写、create-app 注入
     └── 聊天 / 应用 Tab WebView / Docker / Agent 运维
```

| 目录 | 说明 |
|------|------|
| [`app/`](app/) | Flutter 客户端（Android 为主） |
| [`gateway/`](gateway/) | Node.js BFF（Fastify，Docker 部署） |
| [`docs/`](docs/) | 架构、应用项目、部署文档 |

> 英文说明见 [README.en.md](README.en.md)

---

## 项目做什么？

1. **移动端聊天**：OpenAI 兼容 SSE，支持图片 inline、Markdown、Gateway 媒体内嵌播放。
2. **应用 Tab**：WebView 加载 Gateway 托管的 HTML/Node 小应用（static / dynamic）。
3. **Create App 模式**：聊天中开启后，Gateway 向 Hermes **强制注入** create-app SKILL + HermesApp 示例 + **委派简报**（OpenCode / Claude Code 等外部工具须附带目录规范）。
4. **HermesApp 宿主 API**：选图、选文件、保存到相册/下载目录、分享、录音等（WebView Bridge）。
5. **运维控制台**：Docker 容器、Hermes Agent 配置、备份、定时任务、消息网关等（经 Gateway 代理）。

---

## 当前进度（已实现）

| 模块 | 状态 |
|------|------|
| Gateway 登录 JWT、聊天 SSE 透传 | ✅ |
| 会话列表 / 历史（Dashboard 代理） | ✅ |
| 媒体 URL 改写、`MEDIA:file://` 内嵌 | ✅ |
| 应用项目 static/dynamic 托管与 API 反代 | ✅ |
| HermesApp Bridge + snippets 注入 | ✅ |
| Create App 模式 + 目标项目锁定 + 委派 Brief | ✅ |
| 开屏 Shader 动画 + 冷启动优化 | ✅ |
| Docker 管理、Agent 管理 API | ✅ |
| iOS 工程 | ❌ 未纳入（仅 Android） |

详细架构见 [`docs/架构计划书.md`](docs/架构计划书.md)。

---

## 环境要求

| 组件 | 版本 |
|------|------|
| Flutter | 3.11+（Dart 3.11+） |
| Node.js | 20+ |
| Docker | 部署 Gateway 推荐 |
| Hermes | 宿主机 API Server `:8642`、Dashboard `:9119` |

---

## Android 安装（Release APK）

面向使用者：**直接从 GitHub Releases 安装**，不用编译源码。

1. 打开 **[Releases 页面](https://github.com/learnMoresss/flutterhermens/releases)**，进入最新版本（[Latest](https://github.com/learnMoresss/flutterhermens/releases/latest)）。
2. 在 **Assets** 中下载安装包（[v1.0.0+](https://github.com/learnMoresss/flutterhermens/releases/latest)）：

| 文件 | 适用 |
|------|------|
| **app-release.apk** | 通用包（不确定机型时选这个） |
| **app-arm64-v8a-release.apk** | 主流 64 位 Android 手机（推荐） |
| **app-armeabi-v7a-release.apk** | 旧 32 位设备 |
| **app-x86_64-release.apk** | 模拟器 / x86 设备 |

3. 传到手机安装；若系统提示「未知来源」，在设置中允许该安装来源。
4. 首次打开 App → **设置 / 初次配置** 中填写 **Gateway 地址**（如 `http://your-server:3000`）→ 登录。

> App 只负责连接你已部署的 Gateway；**Gateway 与 Hermes 仍需在服务器侧单独部署**（见下文「快速开始」）。  
> 无现成 Gateway 的用户需先按 [`docs/deploy/README.md`](docs/deploy/README.md) 部署 BFF。

### 命令行安装（ADB，可选）

```bash
# 将 YOUR_VERSION 换成 Release 标签，如 v1.0.0
gh release download --repo learnMoresss/flutterhermens --pattern "*.apk" --dir .
adb install -r app-release.apk
```

---

## 快速开始

### 1. 启动 Gateway

```bash
cd gateway
cp .env.example .env
# 编辑 .env：JWT_SECRET、GATEWAY_AUTH_PASSWORD、HERMES_API_ORIGIN、HERMES_API_SERVER_KEY 等
npm install
npm run dev
# 或 Docker：
docker compose up -d --build
```

验证：

```bash
curl -s http://127.0.0.1:3000/health
```

环境变量模板与部署说明：[`docs/deploy/README.md`](docs/deploy/README.md) · [`gateway/AUTH.md`](gateway/AUTH.md)

### 2. 运行 Flutter App

```bash
cd app
flutter pub get
flutter run --release
```

Release APK（**维护者发布到 GitHub，见 [`docs/deploy/RELEASE.md`](docs/deploy/RELEASE.md)**）：

```bash
cd app
flutter build apk --release
# 本地产物: app/build/app/outputs/flutter-apk/app-release.apk
# 上传至 GitHub Release Assets，供用户下载安装
```

首次打开：在设置页填写 **Gateway 地址**（如 `http://192.168.x.x:3000`）→ 登录 → 使用聊天 / 应用 Tab。

### 3. Create App（可选）

1. 聊天页开启 **「创建 App」** 模式  
2. 描述要做的工具页面  
3. Hermes 在 `GATEWAY_PROJECTS_ROOT`（默认 `/data/hermes-projects/{slug}/`）创建项目  
4. 在 **应用 Tab** 打开；dynamic 类型需点「启动」

规范：[`gateway/skills/create-app/SKILL.md`](gateway/skills/create-app/SKILL.md) · [`docs/hermes-projects/PROJECTS.md`](docs/hermes-projects/PROJECTS.md)

---

## 仓库结构

```text
flutterhermens/
├── app/                 # Flutter UI
│   ├── lib/features/    # chat, apps, splash, docker, agent…
│   ├── shaders/         # 开屏 GPU shader
│   └── assets/          #  bundled 项目 HTML 等
├── gateway/
│   ├── src/             # Fastify 路由与 BFF 逻辑
│   ├── skills/create-app/
│   └── docker-compose.yml
├── docs/
│   ├── 架构计划书.md
│   ├── deploy/          # 可提交的 env 模板
│   └── hermes-projects/ # 项目模板与 HOST-API
└── README.md
```

---

## 安全与 Git 规范

**切勿提交：**

- SSH 私钥（`*.pem`、`*.key`）
- 含真实密码的 `.env` / `gateway-deploy.env.local`
- 本地 `scripts/` 目录（已在 `.gitignore`）
- 临时视频、构建产物（`gateway-dist.tgz`、`app/build/`）

可提交：`**/*.env.example`、`docs/deploy/*.example`

若私钥曾误提交，须轮换密钥并从 Git 历史中清除。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [README.en.md](README.en.md) | English README |
| [docs/架构计划书.md](docs/架构计划书.md) | 架构与风险 |
| [gateway/README.md](gateway/README.md) | Gateway 接口与本地开发 |
| [gateway/AUTH.md](gateway/AUTH.md) | 鉴权、Docker、create_app_mode |
| [docs/hermes-projects/HOST-API.md](docs/hermes-projects/HOST-API.md) | HermesApp WebView API |
| [docs/hermes-projects/PROJECTS.md](docs/hermes-projects/PROJECTS.md) | 应用项目目录规范 |
| [docs/deploy/README.md](docs/deploy/README.md) | 部署与环境变量模板 |
| [docs/deploy/RELEASE.md](docs/deploy/RELEASE.md) | **发布 Release APK 到 GitHub** |

---

## License

本项目采用 [MIT License](LICENSE) 开源。
