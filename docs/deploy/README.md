# 部署与环境变量

本目录提供 **可提交到 Git** 的环境变量模板。真实密码、私钥、本地部署脚本 **不要** 放进仓库。

## 为什么 `scripts/` 不在 Git 里？

`scripts/` 含 Windows/WSL 一键部署、SSH 密码交互、个人服务器运维脚本，容易误带密钥或环境相关信息，已在根目录 `.gitignore` 中排除。

若你本地已有 `scripts/`，可继续使用；新克隆仓库的用户请按下方 **Gateway Docker** 或 **手动部署** 操作。

## Gateway 环境变量

1. 复制 [`gateway-deploy.env.example`](gateway-deploy.env.example) → `gateway/.env`
2. 填写 `JWT_SECRET`、`GATEWAY_AUTH_*`、`HERMES_API_*` 等
3. 完整说明见 [`gateway/AUTH.md`](../../gateway/AUTH.md) 与 [`gateway/.env.example`](../../gateway/.env.example)

## 远程 SSH（可选）

复制 [`hermes-remote.env.example`](hermes-remote.env.example) 到本机 `~/.hermes-remote.env`（`chmod 600`），**勿提交**。

## Gateway Docker（推荐）

```bash
cd gateway
cp .env.example .env   # 或合并 docs/deploy/gateway-deploy.env.example 中的项
docker compose up -d --build
curl -s http://127.0.0.1:3000/health
```

## Flutter App

```bash
cd app
flutter pub get
flutter run --release
# Release APK: flutter build apk --release
# 产物: app/build/app/outputs/flutter-apk/app-release.apk
```

App 首次启动在「设置」中填写 Gateway 地址（如 `http://your-host:3000`），再登录。
