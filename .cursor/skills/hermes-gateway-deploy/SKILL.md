---
name: hermes-gateway-deploy
description: >-
  Uploads the Hermes gateway tarball over SSH and restarts it on the remote host
  (native Node or Docker compose). Use when the user asks to deploy the gateway,
  upload gateway to the server, SSH restart, gateway-docker-up, or
  scripts/hermes-remote.sh.
disable-model-invocation: true
---

# Hermes Gateway 远程部署（SSH）

## 原则

- **永远不要把 SSH 密码、私钥内容写进仓库、技能或可被提交的 `.env`。** 用户在聊天里提供的密码只用于当次会话说明，不写入文件。
- 私钥文件（如 `syl.pem`）应放在本机安全路径，并优先加入 **`.gitignore`**，避免误提交。

## 本仓库入口

- 自动化（密码走环境变量 + `sshpass`，适合 WSL）：`scripts/hermes-remote.sh`。
- **Windows 本机（推荐）**：双击 `scripts/deploy-gateway.cmd`，或在 PowerShell 里执行  
  `powershell -ExecutionPolicy Bypass -File .\scripts\deploy-gateway-windows.ps1`  
  依赖系统自带的 `tar`、`scp`、`ssh`（设置 → 可选功能 → OpenSSH 客户端）。
- 推荐把变量写在 **`~/.hermes-remote.env`**（`chmod 600`），由 `~/.bashrc` 自动 `source`（仅 WSL/类 Unix）。

## 认证方式

1. **公钥免密**：只设置 `HERMES_SSH_KEY`（不要设置 `HERMES_SSH_PASS`）。
2. **仅密码**：只设置 `HERMES_SSH_PASS`，并安装 `sshpass`；脚本会加 `PubkeyAuthentication=no`。
3. **「带了 -i 密钥仍要密码」**（服务器未登记你的公钥）：同时设置 **`HERMES_SSH_KEY` + `HERMES_SSH_PASS`**，且已安装 **`sshpass`**；脚本会用 `sshpass` 包装 `ssh`/`scp`，并可保留 `-i` 以便先尝试公钥再自动填密码。

WSL 下若密钥在项目根目录，路径形如：`/mnt/e/testXM/flutterhermens/syl.pem`（按实际盘符与目录改）。

## 常用命令

```bash
# 安装 sshpass（Ubuntu / WSL）
sudo apt update && sudo apt install -y sshpass

cd /mnt/e/testXM/flutterhermens   # 按实际仓库路径
source ~/.hermes-remote.env       # 或在此 shell 内 export 变量（勿把密码写进仓库）



# Docker：上传 + 远端 build + up（会 sudo docker，需 HERMES_SSH_PASS）

bash scripts/hermes-remote.sh gateway-docker-up



# 仅上传压缩包

bash scripts/hermes-remote.sh upload-gateway



# 原生 Node：解压后的 ~/gateway 上 npm ci + build + 后台 node

bash scripts/hermes-remote.sh gateway-restart

```



## 远端 sudo



`gateway-docker-up` 在远端用 `sudo docker compose`，`HERMES_SSH_PASS` 通常与 **ubuntu 登录密码**相同（脚本内通过 `sudo -S` 传入）。若已配置 **无密码 sudo**，仍需按脚本要求导出变量（脚本会检测是否为空）。



## 与 Cursor 沙箱



在无交互 SSH、无本机 `~/.hermes-remote.env` 或未安装 `sshpass` 的环境里，代理可能**无法**替用户完成登录；请用户在本机终端执行上述命令。


