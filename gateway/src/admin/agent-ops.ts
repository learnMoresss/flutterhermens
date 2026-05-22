import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { getHermesHome } from './agent-home.js';
import { runHermesCli } from './hermes-cli.js';

const ALLOWED_LOG_FILES = new Set(['gateway.log', 'agent.log', 'api.log', 'hermes.log']);

export function readHermesLogs(file: string, tail = 500): { content: string; path: string } {
  const safeName = ALLOWED_LOG_FILES.has(file) ? file : 'gateway.log';
  const logPath = join(getHermesHome(), 'logs', safeName);
  if (!existsSync(logPath)) {
    return { content: '', path: logPath };
  }
  try {
    const raw = readFileSync(logPath, 'utf-8');
    const lines = raw.split('\n');
    const slice = lines.slice(Math.max(0, lines.length - tail));
    return { content: slice.join('\n'), path: logPath };
  } catch {
    return { content: '', path: logPath };
  }
}

export async function runHermesDoctor(): Promise<{ ok: boolean; output: string }> {
  const r = await runHermesCli(['doctor'], 120_000);
  const output = [r.stdout, r.stderr].filter(Boolean).join('\n').trim();
  return { ok: r.code === 0, output: output || '(无输出)' };
}

export function listMcpServers(): Array<{ name: string; command: string }> {
  const configFile = join(getHermesHome(), 'config.yaml');
  if (!existsSync(configFile)) return [];
  const content = readFileSync(configFile, 'utf-8');
  const servers: Array<{ name: string; command: string }> = [];
  const lines = content.split('\n');
  let inMcp = false;
  let currentName = '';
  for (const line of lines) {
    if (/^\s*mcp_servers\s*:/.test(line)) {
      inMcp = true;
      continue;
    }
    if (inMcp && /^[a-z_]/i.test(line) && !/^\s/.test(line)) {
      inMcp = false;
    }
    if (!inMcp) continue;
    const nameMatch = line.match(/^\s*-\s*name:\s*["']?([^"'\n#]+)["']?/);
    if (nameMatch) {
      currentName = nameMatch[1].trim();
      continue;
    }
    const cmdMatch = line.match(/^\s*command:\s*["']?([^"'\n#]+)["']?/);
    if (cmdMatch && currentName) {
      servers.push({ name: currentName, command: cmdMatch[1].trim() });
      currentName = '';
    }
  }
  return servers;
}

export function listLogFiles(): string[] {
  const logsDir = join(getHermesHome(), 'logs');
  if (!existsSync(logsDir)) return [];
  try {
    return readdirSync(logsDir).filter((f) => f.endsWith('.log'));
  } catch {
    return [];
  }
}
