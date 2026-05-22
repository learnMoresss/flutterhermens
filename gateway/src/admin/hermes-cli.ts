import { execFile } from 'node:child_process';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { getHermesHome } from './agent-home.js';

const execFileAsync = promisify(execFile);

export function getHermesRepo(): string {
  const raw = process.env.HERMES_REPO?.trim();
  if (raw) return raw;
  return join(getHermesHome(), 'hermes-agent');
}

export function getHermesPython(): string {
  const raw = process.env.HERMES_PYTHON?.trim();
  if (raw) return raw;
  return 'python3';
}

export async function runHermesCli(
  subArgs: string[],
  timeoutMs = 120_000,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const python = getHermesPython();
  const repo = getHermesRepo();
  const args = ['-m', 'hermes', ...subArgs];
  try {
    const { stdout, stderr } = await execFileAsync(python, args, {
      cwd: repo,
      env: { ...process.env, HERMES_HOME: getHermesHome() },
      timeout: timeoutMs,
      maxBuffer: 10 * 1024 * 1024,
    });
    return { code: 0, stdout: stdout.toString(), stderr: stderr.toString() };
  } catch (err: unknown) {
    const e = err as { code?: number; stdout?: Buffer; stderr?: Buffer; message?: string };
    return {
      code: typeof e.code === 'number' ? e.code : 1,
      stdout: e.stdout?.toString() ?? '',
      stderr: e.stderr?.toString() ?? e.message ?? '',
    };
  }
}
