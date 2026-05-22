# Hermes Gateway（Node BFF）

移动端与 Hermes API Server / Dashboard 之间的聚合层。

- 主文档：[../README.md](../README.md) · [AUTH.md](AUTH.md)
- 环境模板：[../docs/deploy/gateway-deploy.env.example](../docs/deploy/gateway-deploy.env.example)

## 本地开发

```bash
cp .env.example .env
npm install
npm run dev
```

## Docker 部署

```bash
docker compose up -d --build
curl -s http://127.0.0.1:3000/health
```

> 本地 `scripts/` 部署脚本不入 Git；见 [docs/deploy/README.md](../docs/deploy/README.md)。

## 主要 API

| 路径 | 说明 |
|------|------|
| `POST /v1/login` | App 登录 → JWT |
| `POST /v1/chat/completions` | 聊天 SSE；可选 `create_app_mode` |
| `GET /v1/projects/:slug/` | 应用 WebView |
| `GET /v1/hermes-app/host.js` | HermesApp SDK |

完整列表见 [AUTH.md](AUTH.md)。
