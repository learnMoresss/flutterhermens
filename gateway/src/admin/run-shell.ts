import { spawn } from 'node:child_process';

export async function runShellLine(
  line: string,
  timeoutMs: number,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const trimmed = line.trim();
  if (!trimmed) {
    throw new Error('未配置 shell 命令');
  }
  if (trimmed.length > 4000) {
    throw new Error('命令过长');
  }
  return new Promise((resolve, reject) => {
    const child = spawn(trimmed, {
      shell: true,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout?.on('data', (c) => {
      stdout += c.toString();
    });
    child.stderr?.on('data', (c) => {
      stderr += c.toString();
    });
    const t = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`命令超时 ${timeoutMs}ms`));
    }, timeoutMs);
    child.on('error', (err) => {
      clearTimeout(t);
      reject(err);
    });
    child.on('close', (code) => {
      clearTimeout(t);
      resolve({ code: code ?? 1, stdout, stderr });
    });
  });
}
