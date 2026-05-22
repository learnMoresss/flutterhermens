import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { getProjectsRoot } from './projects-manager.js';

const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

export type ProjectLockInfo = {
  locked: boolean;
  reason: string;
  since: string;
  by: 'chat' | 'admin' | 'lifecycle';
};

const LOCKS_FILE = '.gateway-locks.json';
const locks = new Map<string, ProjectLockInfo>();
/** 同一项目并发 chat 流：引用计数，避免提前解锁 */
const lockRefs = new Map<string, number>();

function locksPath(): string {
  return join(getProjectsRoot(), LOCKS_FILE);
}

function loadLocksFromDisk(): void {
  locks.clear();
  lockRefs.clear();
  const p = locksPath();
  if (!existsSync(p)) return;
  try {
    const raw = JSON.parse(readFileSync(p, 'utf8')) as Record<string, ProjectLockInfo>;
    for (const [k, v] of Object.entries(raw)) {
      if (v?.locked) {
        locks.set(k, v);
        lockRefs.set(k, 1);
      }
    }
  } catch {
    /* ignore corrupt */
  }
}

function persistLocks(): void {
  const obj: Record<string, ProjectLockInfo> = {};
  for (const [k, v] of locks.entries()) obj[k] = v;
  writeFileSync(locksPath(), JSON.stringify(obj, null, 2), 'utf8');
}

export function initProjectLocks(): void {
  loadLocksFromDisk();
}

export function getProjectLock(slug: string): ProjectLockInfo | null {
  return locks.get(slug) ?? null;
}

export function isProjectLocked(slug: string): boolean {
  return locks.get(slug)?.locked === true;
}

export function lockProject(
  slug: string,
  reason: string,
  by: ProjectLockInfo['by'] = 'chat',
): ProjectLockInfo {
  assertValidProjectSlug(slug);
  const refs = (lockRefs.get(slug) ?? 0) + 1;
  lockRefs.set(slug, refs);
  const prev = locks.get(slug);
  const info: ProjectLockInfo = {
    locked: true,
    reason,
    since: prev?.since ?? new Date().toISOString(),
    by: prev?.by ?? by,
  };
  locks.set(slug, info);
  persistLocks();
  return info;
}

export function unlockProject(slug: string): void {
  const refs = (lockRefs.get(slug) ?? 0) - 1;
  if (refs <= 0) {
    lockRefs.delete(slug);
    if (!locks.has(slug)) return;
    locks.delete(slug);
    persistLocks();
    return;
  }
  lockRefs.set(slug, refs);
}

export function assertProjectNotLocked(slug: string): void {
  const lock = getProjectLock(slug);
  if (lock?.locked) {
    throw new Error(`项目「${slug}」正在更新（${lock.reason}），请稍候再操作`);
  }
}

export async function withProjectLifecycleLock<T>(
  slug: string,
  reason: string,
  fn: () => Promise<T>,
): Promise<T> {
  assertProjectNotLocked(slug);
  lockProject(slug, reason, 'lifecycle');
  try {
    return await fn();
  } finally {
    unlockProject(slug);
  }
}

export function attachUnlockOnStreamEnd(stream: NodeJS.ReadableStream, slug: string | undefined): void {
  if (!slug) return;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    unlockProject(slug);
  };
  stream.on('end', finish);
  stream.on('close', finish);
  stream.on('error', finish);
}

function assertValidProjectSlug(slug: string): void {
  if (!SLUG_RE.test(slug)) throw new Error('无效的项目 ID');
  const root = getProjectsRoot();
  const dir = resolve(root, slug);
  if (!dir.startsWith(root + '/') && dir !== root) throw new Error('无效的项目 ID');
  if (!existsSync(join(dir, 'project.json'))) throw new Error(`项目不存在：${slug}`);
}
