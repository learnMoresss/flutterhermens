import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import type { AppConfig } from '../config.js';

const RETENTION_FILE = '.gateway-retention.json';
const SCHEDULE_FILE = '.gateway-schedule.json';
const BACKUP_PREFIX = 'hermes-backup-';

export type BackupEntry = {
  filename: string;
  sizeBytes: number;
  createdAt: string;
};

function safeBackupFilename(name: string): boolean {
  if (!name.endsWith('.tgz')) return false;
  if (name.includes('/') || name.includes('..')) return false;
  return /^hermes-backup-[0-9TZ.-]+\.tgz$/.test(name);
}

async function readJson<T>(file: string, fallback: T): Promise<T> {
  try {
    const raw = await fs.readFile(file, 'utf8');
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

async function writeJson(file: string, data: unknown): Promise<void> {
  await fs.writeFile(file, JSON.stringify(data, null, 2), 'utf8');
}

export async function getEffectiveMaxBackups(cfg: AppConfig): Promise<number> {
  const p = path.join(cfg.HERMES_BACKUP_DIR, RETENTION_FILE);
  const j = await readJson<{ maxBackups?: number }>(p, {});
  if (typeof j.maxBackups === 'number' && j.maxBackups >= 1 && j.maxBackups <= 365) {
    return j.maxBackups;
  }
  return cfg.HERMES_BACKUP_MAX;
}

export async function setMaxBackups(cfg: AppConfig, max: number): Promise<void> {
  await fs.mkdir(cfg.HERMES_BACKUP_DIR, { recursive: true });
  const p = path.join(cfg.HERMES_BACKUP_DIR, RETENTION_FILE);
  await writeJson(p, { maxBackups: max });
}

export async function listBackups(cfg: AppConfig): Promise<BackupEntry[]> {
  await fs.mkdir(cfg.HERMES_BACKUP_DIR, { recursive: true });
  const names = await fs.readdir(cfg.HERMES_BACKUP_DIR);
  const entries: BackupEntry[] = [];
  for (const name of names) {
    if (!safeBackupFilename(name)) continue;
    const fp = path.join(cfg.HERMES_BACKUP_DIR, name);
    const st = await fs.stat(fp);
    if (!st.isFile()) continue;
    entries.push({
      filename: name,
      sizeBytes: st.size,
      createdAt: st.mtime.toISOString(),
    });
  }
  entries.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  return entries;
}

async function prune(cfg: AppConfig): Promise<void> {
  const max = await getEffectiveMaxBackups(cfg);
  const all = await listBackups(cfg);
  if (all.length <= max) return;
  const toRemove = all.slice(max);
  for (const e of toRemove) {
    await fs.unlink(path.join(cfg.HERMES_BACKUP_DIR, e.filename)).catch(() => {});
  }
}

function runTar(args: string[], timeoutMs: number): Promise<{ code: number; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn('tar', args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    const t = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`tar timeout after ${timeoutMs}ms`));
    }, timeoutMs);
    child.stderr?.on('data', (c) => {
      stderr += c.toString();
    });
    child.on('error', (err) => {
      clearTimeout(t);
      reject(err);
    });
    child.on('close', (code) => {
      clearTimeout(t);
      resolve({ code: code ?? 1, stderr });
    });
  });
}

/** 创建 tar.gz：在 parent 下打包 base 目录名 */
export async function createHermesArchive(cfg: AppConfig): Promise<string> {
  await fs.mkdir(cfg.HERMES_BACKUP_DIR, { recursive: true });
  const src = path.resolve(cfg.HERMES_BACKUP_SOURCE);
  const parent = path.dirname(src);
  const base = path.basename(src);
  await fs.access(src).catch(() => {
    throw new Error(`HERMES_BACKUP_SOURCE 不可读: ${src}`);
  });
  const stamp = new Date().toISOString().replace(/[:]/g, '-').replace(/\.\d{3}Z$/, 'Z');
  const filename = `${BACKUP_PREFIX}${stamp}.tgz`;
  const dest = path.join(cfg.HERMES_BACKUP_DIR, filename);
  const { code, stderr } = await runTar(['-czf', dest, '-C', parent, base], 600_000);
  if (code !== 0) {
    await fs.unlink(dest).catch(() => {});
    throw new Error(`tar 打包失败: ${stderr.slice(0, 500)}`);
  }
  await prune(cfg);
  return filename;
}

export async function restoreHermesArchive(cfg: AppConfig, filename: string): Promise<void> {
  if (!safeBackupFilename(filename)) {
    throw new Error('非法备份文件名');
  }
  const archive = path.join(cfg.HERMES_BACKUP_DIR, filename);
  await fs.access(archive).catch(() => {
    throw new Error('备份文件不存在');
  });
  const src = path.resolve(cfg.HERMES_BACKUP_SOURCE);
  const parent = path.dirname(src);
  await fs.mkdir(parent, { recursive: true });
  const { code, stderr } = await runTar(['-xzf', archive, '-C', parent], 600_000);
  if (code !== 0) {
    throw new Error(`tar 解压失败: ${stderr.slice(0, 500)}`);
  }
}

export async function getScheduleState(cfg: AppConfig): Promise<{ lastDailyBackupAt: string | null }> {
  const p = path.join(cfg.HERMES_BACKUP_DIR, SCHEDULE_FILE);
  const j = await readJson<{ lastDailyBackupAt?: string | null }>(p, {});
  return { lastDailyBackupAt: j.lastDailyBackupAt ?? null };
}

export async function setLastDailyBackup(cfg: AppConfig, iso: string): Promise<void> {
  await fs.mkdir(cfg.HERMES_BACKUP_DIR, { recursive: true });
  const p = path.join(cfg.HERMES_BACKUP_DIR, SCHEDULE_FILE);
  await writeJson(p, { lastDailyBackupAt: iso });
}

/** 若已过「上次日历日」且当前小时 >= 配置整点，则执行一次备份并记录日期 */
export async function maybeRunScheduledDailyBackup(cfg: AppConfig): Promise<boolean> {
  await fs.mkdir(cfg.HERMES_BACKUP_DIR, { recursive: true });
  const now = new Date();
  if (now.getHours() < cfg.HERMES_DAILY_BACKUP_HOUR) {
    return false;
  }
  const { lastDailyBackupAt } = await getScheduleState(cfg);
  if (lastDailyBackupAt) {
    const last = new Date(lastDailyBackupAt);
    if (
      last.getFullYear() === now.getFullYear() &&
      last.getMonth() === now.getMonth() &&
      last.getDate() === now.getDate()
    ) {
      return false;
    }
  }
  await createHermesArchive(cfg);
  await setLastDailyBackup(cfg, now.toISOString());
  return true;
}
