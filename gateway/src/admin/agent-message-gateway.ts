import { existsSync, readFileSync } from 'node:fs';

import { getPlatformEnabled, setPlatformEnabled } from './agent-env.js';
import { hermesPath } from './agent-home.js';
import { runShellLine } from './run-shell.js';

function isGatewayPidRunning(): boolean {
  const pidFile = hermesPath('gateway.pid');
  if (!existsSync(pidFile)) return false;
  try {
    const pid = parseInt(readFileSync(pidFile, 'utf-8').trim(), 10);
    if (Number.isNaN(pid)) return false;
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function getMessageGatewayStatus(): Promise<{
  running: boolean;
  pidFileExists: boolean;
}> {
  const custom = process.env.HERMES_GATEWAY_STATUS_SHELL?.trim();
  if (custom) {
    const r = await runShellLine(custom, 15_000);
    const running = r.code === 0 && /running|true|1/i.test(r.stdout);
    return { running, pidFileExists: existsSync(hermesPath('gateway.pid')) };
  }
  return {
    running: isGatewayPidRunning(),
    pidFileExists: existsSync(hermesPath('gateway.pid')),
  };
}

export async function startMessageGateway(): Promise<{ ok: boolean; error?: string }> {
  const line = process.env.HERMES_GATEWAY_START_SHELL?.trim();
  if (!line) {
    return { ok: false, error: '未配置 HERMES_GATEWAY_START_SHELL' };
  }
  const r = await runShellLine(line, 60_000);
  if (r.code !== 0) {
    return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '启动失败' };
  }
  return { ok: true };
}

export async function stopMessageGateway(): Promise<{ ok: boolean; error?: string }> {
  const line = process.env.HERMES_GATEWAY_STOP_SHELL?.trim();
  if (!line) {
    return { ok: false, error: '未配置 HERMES_GATEWAY_STOP_SHELL' };
  }
  const r = await runShellLine(line, 60_000);
  if (r.code !== 0) {
    return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '停止失败' };
  }
  return { ok: true };
}

export { getPlatformEnabled, setPlatformEnabled };
