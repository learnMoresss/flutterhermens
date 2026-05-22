import fs from 'node:fs';
import os from 'node:os';

const DEFAULT_HERMES_PORT = '8080';

function normalizePort(raw: string | undefined): string {
  const s = (raw ?? '').trim();
  if (!/^\d+$/.test(s)) return DEFAULT_HERMES_PORT;
  const n = Number(s);
  if (n < 1 || n > 65535) return DEFAULT_HERMES_PORT;
  return String(n);
}

/** 优先私网 IPv4，便于同机/局域网 Hermes。 */
export function pickLanIPv4(): string | null {
  const nets = os.networkInterfaces();
  const candidates: { addr: string; score: number }[] = [];
  for (const entries of Object.values(nets)) {
    if (!entries) continue;
    for (const net of entries) {
      const v4 = net.family === 'IPv4' || String(net.family) === '4';
      if (!v4 || net.internal) continue;
      const addr = net.address;
      let score = 100;
      if (addr.startsWith('192.168.')) score = 0;
      else if (addr.startsWith('10.')) score = 1;
      else if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(addr)) score = 2;
      candidates.push({ addr, score });
    }
  }
  if (!candidates.length) return null;
  candidates.sort((a, b) => a.score - b.score || a.addr.localeCompare(b.addr));
  return candidates[0]!.addr;
}

function runningInsideDocker(): boolean {
  try {
    return fs.existsSync('/.dockerenv');
  } catch {
    return false;
  }
}

/**
 * Linux 容器内读默认路由网关（/proc/net/route 中 Destination=00000000 的 Gateway），
 * 通常为 `172.18.0.1` 这类**宿主机在 bridge 上的地址**，用于访问宿主机监听的 Hermes。
 */
function readLinuxDefaultRouteGatewayIPv4(): string | null {
  if (process.platform !== 'linux') return null;
  try {
    const raw = fs.readFileSync('/proc/net/route', 'utf8');
    for (const line of raw.split('\n').slice(1)) {
      const cols = line.trim().split(/\s+/);
      if (cols.length < 3) continue;
      const dest = cols[1]?.toLowerCase() ?? '';
      const gwHex = cols[2]?.toLowerCase() ?? '';
      if (dest !== '00000000' || !gwHex || gwHex === '00000000') continue;
      const n = Number.parseInt(gwHex, 16);
      if (!Number.isFinite(n)) continue;
      const buf = Buffer.allocUnsafe(4);
      buf.writeUInt32LE(n >>> 0, 0);
      return `${buf[0]}.${buf[1]}.${buf[2]}.${buf[3]}`;
    }
  } catch {
    return null;
  }
  return null;
}

/**
 * 在 zod 解析前改写 `process.env.HERMES_ORIGIN`。
 * - `auto` / `detect` / 空：若在 Docker 容器内（存在 `/.dockerenv`），优先用 Linux 默认路由网关
 *   （指向宿主机，避免误用**本容器**的 eth IP）；否则取本机第一个可用私网 IPv4 + 端口（默认 8080）
 * - `docker-host`：host.docker.internal（Docker Desktop 访问宿主机）
 * - `docker-bridge`：172.17.0.1（Linux 默认网桥上的宿主机，视环境可能不可用）
 * - 仅 IPv4 或 `host:port` 无 scheme：补全为 `http://…`
 *
 * 端口来自 `HERMES_ORIGIN_AUTO_PORT` 或 `HERMES_DEFAULT_PORT`，缺省 8080。
 */
export function resolveHermesOriginEnv(): void {
  const port = normalizePort(process.env.HERMES_ORIGIN_AUTO_PORT ?? process.env.HERMES_DEFAULT_PORT);
  let raw = (process.env.HERMES_ORIGIN ?? '').trim();
  if (!raw) {
    raw = 'auto';
  }
  const lower = raw.toLowerCase();

  if (lower === 'auto' || lower === 'detect') {
    let ip: string | null = null;
    if (runningInsideDocker()) {
      ip = readLinuxDefaultRouteGatewayIPv4();
    }
    if (!ip) {
      ip = pickLanIPv4();
    }
    if (!ip) {
      throw new Error(
        'HERMES_ORIGIN=auto 但未检测到可用的非回环 IPv4。请显式填写 HERMES_ORIGIN（Docker 可试 docker-host）。',
      );
    }
    process.env.HERMES_ORIGIN = `http://${ip}:${port}`;
    return;
  }

  if (lower === 'docker-host') {
    process.env.HERMES_ORIGIN = `http://host.docker.internal:${port}`;
    return;
  }

  if (lower === 'docker-bridge') {
    process.env.HERMES_ORIGIN = `http://172.17.0.1:${port}`;
    return;
  }

  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(raw)) {
    process.env.HERMES_ORIGIN = `http://${raw}:${port}`;
    return;
  }

  if (/^[\w.-]+:\d+$/.test(raw) && !raw.includes('://')) {
    process.env.HERMES_ORIGIN = `http://${raw}`;
  }
}

const DEFAULT_API_PORT = '8642';
const DEFAULT_DASHBOARD_PORT = '9119';

function resolveOriginEnvVar(
  envKey: 'HERMES_API_ORIGIN' | 'HERMES_DASHBOARD_ORIGIN',
  defaultPort: string,
  portOverrideEnvKeys: string[],
): void {
  let raw = (process.env[envKey] ?? '').trim();
  if (!raw) return;

  const port = normalizePort(
    portOverrideEnvKeys.map((k) => process.env[k]).find((v) => v?.trim()) ?? defaultPort,
  );
  const lower = raw.toLowerCase();

  if (lower === 'auto' || lower === 'detect') {
    let ip: string | null = null;
    if (runningInsideDocker()) {
      ip = readLinuxDefaultRouteGatewayIPv4();
    }
    if (!ip) ip = pickLanIPv4();
    if (!ip) {
      throw new Error(`${envKey}=auto 但未检测到可用的非回环 IPv4。请显式填写完整 URL。`);
    }
    process.env[envKey] = `http://${ip}:${port}`;
    return;
  }

  if (lower === 'docker-host') {
    process.env[envKey] = `http://host.docker.internal:${port}`;
    return;
  }

  if (lower === 'docker-bridge') {
    process.env[envKey] = `http://172.17.0.1:${port}`;
    return;
  }

  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(raw)) {
    process.env[envKey] = `http://${raw}:${port}`;
    return;
  }

  if (/^[\w.-]+:\d+$/.test(raw) && !raw.includes('://')) {
    process.env[envKey] = `http://${raw}`;
  }
}

/** 解析 HERMES_API_ORIGIN / HERMES_DASHBOARD_ORIGIN 简写（默认端口 8642 / 9119）。 */
export function resolveHermesApiOriginEnv(): void {
  resolveOriginEnvVar('HERMES_API_ORIGIN', DEFAULT_API_PORT, [
    'HERMES_API_ORIGIN_AUTO_PORT',
    'HERMES_DEFAULT_API_PORT',
  ]);
  resolveOriginEnvVar('HERMES_DASHBOARD_ORIGIN', DEFAULT_DASHBOARD_PORT, [
    'HERMES_DASHBOARD_ORIGIN_AUTO_PORT',
    'HERMES_DEFAULT_DASHBOARD_PORT',
  ]);
}
