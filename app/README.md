# Hermes Mobile Client (`hermes_chat`)

Flutter 薄壳客户端，通过 Gateway BFF 连接 Hermes。

- 主文档：[../README.md](../README.md) · [../README.en.md](../README.en.md)
- **安装 APK**：[GitHub Releases](https://github.com/learnMoresss/flutterhermens/releases/latest)
- 运行：`flutter pub get` → `flutter run --release`
- 打 Release 包：[../docs/deploy/RELEASE.md](../docs/deploy/RELEASE.md)

## 主要功能

| Tab / 页面 | 说明 |
|------------|------|
| 聊天 | SSE 流式、图片、Markdown、Create App 模式 |
| 应用 | WebView + HermesApp 原生能力 |
| 配置 | Hermes 控制台、Agent、定时任务 |
| Docker | 容器管理 |
| 我的 | 主题、Gateway 地址、登出 |

## 目录

```text
lib/features/   # 功能模块
lib/core/       # 网络、路由、主题
shaders/        # 开屏 fragment shader
assets/         #  bundled 项目 HTML 等
```
