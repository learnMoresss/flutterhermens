#!/usr/bin/env bash
set -eu
PASS="${HERMES_SSH_PASS:?请先执行: export HERMES_SSH_PASS=}"
sshpass -p "$PASS" ssh -o PubkeyAuthentication=no ubuntu@119.45.30.73 'bash -se' << ENDREMOTE
set -eu
PW='$PASS'
cd /home/ubuntu
rm -rf gateway
tar xzf gateway-dist.tgz
cd gateway
echo "\$PW" | sudo -S docker compose build --pull
echo "\$PW" | sudo -S docker compose up -d --force-recreate
echo "\$PW" | sudo -S docker compose ps
curl -sS http://127.0.0.1:3000/health || true
echo ""
ENDREMOTE
