# Hermes Mobile (Flutter + Gateway BFF)

A **thin Flutter client** and **Node.js BFF gateway** that bring [Hermes](https://github.com/NousResearch/hermes) to mobile.

**Android APK** → [Download from GitHub Releases](https://github.com/learnMoresss/flutterhermens/releases/latest) (no Flutter SDK required)

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

## Install on Android (Release APK)

For end users: **install from GitHub Releases** — no need to clone or build.

1. Open **[Releases](https://github.com/learnMoresss/flutterhermens/releases)** ([Latest](https://github.com/learnMoresss/flutterhermens/releases/latest)).
2. Under **Assets**, pick an APK ([Latest release](https://github.com/learnMoresss/flutterhermens/releases/latest)):

| File | Use when |
|------|----------|
| **app-release.apk** | Universal (if unsure) |
| **app-arm64-v8a-release.apk** | Most 64-bit phones (recommended) |
| **app-armeabi-v7a-release.apk** | Older 32-bit devices |
| **app-x86_64-release.apk** | Emulator / x86 |

3. Install on your device; allow installs from unknown sources if prompted.
4. First launch → enter your **Gateway URL** in setup (e.g. `http://your-server:3000`) → log in.

> The app connects to **your** Gateway; deploy Gateway + Hermes on a server first ([`docs/deploy/README.md`](docs/deploy/README.md)).

### ADB (optional)

```bash
gh release download --repo learnMoresss/flutterhermens --pattern "*.apk" --dir .
adb install -r app-release.apk
```

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

Release APK (**maintainers publish to GitHub** — see [`docs/deploy/RELEASE.md`](docs/deploy/RELEASE.md)):

```bash
cd app
flutter build apk --release
# Local: app/build/app/outputs/flutter-apk/app-release.apk
# Upload as a GitHub Release asset
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
| [docs/deploy/RELEASE.md](docs/deploy/RELEASE.md) | **Publish APK to GitHub Releases** |

---

## License

Private / no license specified yet — add a LICENSE before public release.
