# Hermes Mobile (Flutter + Gateway BFF)

A **thin Flutter client** and **Node.js BFF gateway** that bring [Hermes](https://github.com/NousResearch/hermes) to mobile.

```text
Flutter App  →  Node Gateway (BFF)  →  Hermes API Server / Dashboard
     │                    │
     │                    └── Hosted app projects, media rewrite, create-app prompts
     └── Chat / Apps WebView / Docker / Agent admin
```

| Directory | Description |
|-----------|-------------|
| [`app/`](app/) | Flutter client (Android-focused) |
| [`gateway/`](gateway/) | Node BFF (Fastify, Docker) |
| [`docs/`](docs/) | Architecture, app projects, deployment |

> 中文说明见 [README.md](README.md)

---

## What is this?

1. **Mobile chat** — OpenAI-compatible SSE, images, Markdown, in-app media playback via Gateway URL rewrite.
2. **Apps tab** — WebView loads HTML/Node mini-apps hosted by Gateway (`static` / `dynamic`).
3. **Create App mode** — Gateway injects full create-app SKILL + HermesApp snippets + **delegation brief** so sub-agents (OpenCode, Claude Code, etc.) follow folder layout.
4. **HermesApp host API** — Native pick image/file, save to gallery/downloads, share, record audio in WebView.
5. **Ops console** — Docker, Hermes Agent config, backups, schedules (proxied through Gateway).

---

## Current status

| Area | Status |
|------|--------|
| Gateway JWT login, chat SSE proxy | Done |
| Sessions list/history (Dashboard proxy) | Done |
| Media rewrite, `MEDIA:file://` in chat | Done |
| App projects (static/dynamic) + API proxy | Done |
| HermesApp bridge + snippet injection | Done |
| Create App mode + project lock + delegation brief | Done |
| Splash shader animation + cold start tuning | Done |
| Docker & Agent admin APIs | Done |
| iOS target | Not included (Android only) |

See [`docs/架构计划书.md`](docs/架构计划书.md) (Chinese architecture doc).

---

## Requirements

| Tool | Version |
|------|---------|
| Flutter | 3.11+ |
| Node.js | 20+ |
| Docker | Recommended for Gateway |
| Hermes | API Server `:8642`, Dashboard `:9119` on host |

---

## Quick start

### Gateway

```bash
cd gateway
cp .env.example .env
# Edit: JWT_SECRET, GATEWAY_AUTH_PASSWORD, HERMES_API_ORIGIN, HERMES_API_SERVER_KEY
npm install
npm run dev
# Or:
docker compose up -d --build
curl -s http://127.0.0.1:3000/health
```

Templates: [`docs/deploy/README.md`](docs/deploy/README.md) · [`gateway/AUTH.md`](gateway/AUTH.md)

### Flutter app

```bash
cd app
flutter pub get
flutter run --release
```

Release APK:

```bash
flutter build apk --release
# Output: app/build/app/outputs/flutter-apk/app-release.apk
```

First launch: set **Gateway URL** in setup (e.g. `http://192.168.x.x:3000`) → login → chat / apps.

### Create App (optional)

1. Enable **Create App** in chat  
2. Describe the mini-app  
3. Hermes creates files under `GATEWAY_PROJECTS_ROOT` (default `/data/hermes-projects/{slug}/`)  
4. Open from **Apps** tab; start dynamic backends from the UI  

Specs: [`gateway/skills/create-app/SKILL.md`](gateway/skills/create-app/SKILL.md) · [`docs/hermes-projects/PROJECTS.md`](docs/hermes-projects/PROJECTS.md)

---

## Repository layout

```text
flutterhermens/
├── app/                 # Flutter UI
├── gateway/             # BFF source + docker-compose
├── docs/
│   ├── deploy/          # Committable env templates
│   └── hermes-projects/
└── README.md
```

---

## Security & Git

**Never commit:**

- SSH private keys (`*.pem`, `*.key`)
- Real passwords in `.env` or `*.local` env files
- Local `scripts/` folder (gitignored)
- Build artifacts and temp media

**Safe to commit:** `*.env.example`, `docs/deploy/*.example`

---

## Documentation

| Doc | Topic |
|-----|--------|
| [README.md](README.md) | Chinese README |
| [gateway/README.md](gateway/README.md) | Gateway APIs & dev |
| [gateway/AUTH.md](gateway/AUTH.md) | Auth, Docker, create_app_mode |
| [docs/hermes-projects/HOST-API.md](docs/hermes-projects/HOST-API.md) | HermesApp WebView API |
| [docs/deploy/README.md](docs/deploy/README.md) | Deployment templates |

---

## License

Private / no license specified yet — add a LICENSE before public release.
