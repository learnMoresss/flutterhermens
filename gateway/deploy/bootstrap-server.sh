#!/usr/bin/env bash
set -euo pipefail
# Run on Linux server AFTER uploading & extracting gateway/ (Ubuntu/Debian 系).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GW_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$GW_ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "[1/4] Docker 未安装，正在安装（官方脚本）..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
fi

echo "[2/4] Docker 版本: $(docker --version)"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "未找到 docker compose，请安装 Docker 20.10+ 后再试。"
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
  SECRET=""
  if command -v openssl >/dev/null 2>&1; then
    SECRET="$(openssl rand -hex 24)"
  elif command -v python3 >/dev/null 2>&1; then
    SECRET="$(python3 -c "import secrets; print(secrets.token_hex(24))")"
  fi
  if [ -n "$SECRET" ]; then
    if grep -q '^JWT_SECRET=' .env 2>/dev/null; then
      sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${SECRET}|" .env
    fi
    echo "[3/4] 已复制 .env 并自动生成 JWT_SECRET"
  else
    echo "[3/4] 已复制 .env，请手动编辑 JWT_SECRET（至少 8 位）后重新运行。"
    exit 1
  fi
else
  echo "[3/4] .env 已存在，跳过"
fi

echo "[4/4] 构建并启动..."
"${COMPOSE[@]}" build --pull
"${COMPOSE[@]}" up -d
"${COMPOSE[@]}" ps

HTTP_PORT="${PORT:-3000}"
if grep -q '^PORT=' .env 2>/dev/null; then
  HTTP_PORT="$(grep '^PORT=' .env | cut -d= -f2- | tr -d '\r')"
fi
echo "---"
echo "本地健康检查: curl -sS http://127.0.0.1:${HTTP_PORT}/health"
