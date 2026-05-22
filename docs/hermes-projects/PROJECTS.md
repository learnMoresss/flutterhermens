# Hermes Mobile 应用项目

App **应用 Tab** 加载 Gateway 托管的页面。Hermes 在 **`/data/hermes-projects/{slug}/`** 下创建项目。

## 类型

| type | 说明 |
|------|------|
| `static` | `public/index.html`，无需启动 |
| `dynamic` | `server/` Node 进程 + `/api` 反代 |

## 模板

- [`_template/static/`](_template/static/)
- [`_template/dynamic/`](_template/dynamic/)

## 技能

- Gateway 内置：[`../../gateway/skills/create-app/SKILL.md`](../../gateway/skills/create-app/SKILL.md)（`create_app_mode: true` 时自动注入 system）
- 可选：复制 SKILL 到 Hermes `~/.hermes/skills/`（本地脚本 `scripts/install-create-app-skill.sh` 仅在本机使用，不入 Git）

## App WebView 宿主 API

内嵌页面须用 **`HermesApp.*`** 选图/文件/录音/保存，勿依赖 drag-drop。见 [`HOST-API.md`](HOST-API.md)。

- 参考实现：[`_examples/image-compressor/`](_examples/image-compressor/)（可覆盖服务器上同名项目）

## App 使用

1. 聊天页开启 **「创建 App」**（或快捷 chip）
2. 描述要做的页面/工具
3. Hermes 创建项目后，到 **应用 Tab** 打开；dynamic 需点启动
