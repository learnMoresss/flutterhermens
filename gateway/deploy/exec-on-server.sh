#!/usr/bin/env bash
# WSL 用法: export HERMES_SSH_PASS='你的SSH密码'; bash gateway/deploy/exec-on-server.sh

set -eu

HOST="119.45.30.73"
USER="ubuntu"
PASS="${HERMES_SSH_PASS:?请先执行: export HERMES_SSH_PASS=}"

ssh_base() {
  sshpass -p "$PASS" ssh -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new "${USER}@${HOST}" "$@"
}

# 未加引号的 heredoc：把本机的 PASS 注入远端 sudo；\$ 留给远端 shell 解析
ssh_base 'bash -se' << ENDREMOTE
set -eu
PW='$PASS'
cd /home/ubuntu
rm -rf gateway
tar xzf gateway-dist.tgz
cd gateway

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  echo "\$PW" | sudo -S bash -c 'curl -fsSL https://get.docker.com | sh'
fi

echo "\$PW" | sudo -S docker --version

if [ ! -f .env ]; then
  cp .env.example .env
  SECRET="\$(openssl rand -hex 24)"
  sed -i "s/^JWT_SECRET=.*/JWT_SECRET=\${SECRET}/" .env
  echo "Generated JWT_SECRET in .env"
fi

echo "\$PW" | sudo -S docker compose build --pull
echo "\$PW" | sudo -S docker compose up -d
echo "\$PW" | sudo -S docker compose ps
echo "--- health ---"
curl -sS http://127.0.0.1:3000/health || true
echo ""
ENDREMOTE
