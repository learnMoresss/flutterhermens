#!/usr/bin/env bash
set -eu
PASS="${HERMES_SSH_PASS:?export HERMES_SSH_PASS=}"
sshpass -p "$PASS" ssh -o PubkeyAuthentication=no ubuntu@119.45.30.73 'bash -se' << ENDREMOTE
set -eu
cd /home/ubuntu/gateway
node -v
npm ci
npm run build
pkill -f "node dist/index.js" || true
sleep 1
set -a
. ./.env
set +a
nohup env NODE_ENV=production node dist/index.js >> /tmp/hermes-gateway.log 2>&1 &
sleep 2
echo "--- health ---"
curl -sS http://127.0.0.1:3000/health && echo ""
ENDREMOTE
