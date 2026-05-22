import { spawn, type ChildProcess } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

import {
  projectManifestSchema,
  type ProjectManifest,
  type ProjectRuntimeStatus,
  type ProjectSummary,
} from './projects-schema.js';
import { getPublicBaseUrl } from './media-serve.js';
import { getProjectLock } from './projects-lock.js';

const REGISTRY_FILE = '.gateway-registry.json';
const PORT_MIN = 40100;
const PORT_MAX = 40200;

type RegistryEntry = {
  port?: number;
  pid?: number;
  status: ProjectRuntimeStatus;
  error?: string;
  startedAt?: string;
};

type RegistryFile = Record<string, RegistryEntry>;

const runtimes = new Map<string, { proc?: ChildProcess; port?: number; status: ProjectRuntimeStatus; error?: string }>();

let projectsRootCached: string | null = null;

export function getProjectsRoot(): string {
  if (projectsRootCached) return projectsRootCached;
  const raw = process.env.GATEWAY_PROJECTS_ROOT?.trim() || '/data/hermes-projects';
  projectsRootCached = resolve(raw);
  if (!existsSync(projectsRootCached)) {
    mkdirSync(projectsRootCached, { recursive: true });
  }
  return projectsRootCached;
}

export function getPublicBaseUrlForProjects(): string {
  return getPublicBaseUrl() || 'http://127.0.0.1:3000';
}

function registryPath(): string {
  return join(getProjectsRoot(), REGISTRY_FILE);
}

function loadRegistry(): RegistryFile {
  const p = registryPath();
  if (!existsSync(p)) return {};
  try {
    return JSON.parse(readFileSync(p, 'utf8')) as RegistryFile;
  } catch {
    return {};
  }
}

function saveRegistry(reg: RegistryFile): void {
  writeFileSync(registryPath(), JSON.stringify(reg, null, 2), 'utf8');
}

function projectDir(slug: string): string {
  const root = getProjectsRoot();
  const dir = resolve(root, slug);
  if (!dir.startsWith(root + '/') && dir !== root) {
    throw new Error('无效的项目 ID');
  }
  return dir;
}

function readManifest(slug: string): ProjectManifest {
  const dir = projectDir(slug);
  const manifestPath = join(dir, 'project.json');
  if (!existsSync(manifestPath)) {
    throw new Error(`缺少 project.json：${slug}`);
  }
  const raw = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const parsed = projectManifestSchema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(parsed.error.issues.map((i) => i.message).join('; '));
  }
  if (parsed.data.id !== slug) {
    throw new Error(`project.json id 必须与目录名一致：${slug}`);
  }
  return parsed.data;
}

function getRuntimeState(slug: string): { status: ProjectRuntimeStatus; port?: number; pid?: number; error?: string } {
  const rt = runtimes.get(slug);
  if (rt) {
    return { status: rt.status, port: rt.port, pid: rt.proc?.pid, error: rt.error };
  }
  const reg = loadRegistry()[slug];
  if (reg) {
    return { status: reg.status, port: reg.port, pid: reg.pid, error: reg.error };
  }
  return { status: 'stopped' };
}

function projectUrl(slug: string): string {
  const base = getPublicBaseUrlForProjects().replace(/\/$/, '');
  return `${base}/v1/projects/${encodeURIComponent(slug)}/`;
}

function lockFields(slug: string): ProjectSummary['lock'] {
  const lock = getProjectLock(slug);
  if (!lock?.locked) return undefined;
  return {
    locked: true,
    reason: lock.reason,
    since: lock.since,
    by: lock.by,
  };
}

export function listProjects(): ProjectSummary[] {
  const root = getProjectsRoot();
  const entries = readdirSync(root, { withFileTypes: true });
  const out: ProjectSummary[] = [];

  for (const ent of entries) {
    if (!ent.isDirectory()) continue;
    if (ent.name.startsWith('.')) continue;
    const slug = ent.name;
    try {
      const manifest = readManifest(slug);
      const rt = getRuntimeState(slug);
      out.push({
        id: manifest.id,
        title: manifest.title,
        type: manifest.type,
        version: manifest.version,
        description: manifest.description,
        status: manifest.type === 'static' ? 'running' : rt.status,
        port: rt.port,
        pid: rt.pid,
        error: rt.error,
        url: projectUrl(slug),
        updatedAt: manifest.updatedAt,
        lock: lockFields(slug),
      });
    } catch {
      /* skip invalid dirs */
    }
  }
  return out.sort((a, b) => a.title.localeCompare(b.title));
}

export function getProject(slug: string): ProjectSummary {
  const manifest = readManifest(slug);
  const rt = getRuntimeState(slug);
  return {
    id: manifest.id,
        title: manifest.title,
        type: manifest.type,
        version: manifest.version,
        description: manifest.description,
        status: manifest.type === 'static' ? 'running' : rt.status,
        port: rt.port,
        pid: rt.pid,
        error: rt.error,
        url: projectUrl(slug),
        updatedAt: manifest.updatedAt,
        lock: lockFields(slug),
  };
}

function pickPort(used: Set<number>): number {
  for (let p = PORT_MIN; p <= PORT_MAX; p++) {
    if (!used.has(p)) return p;
  }
  throw new Error('无可用端口');
}

function collectUsedPorts(): Set<number> {
  const used = new Set<number>();
  for (const rt of runtimes.values()) {
    if (rt.port) used.add(rt.port);
  }
  const reg = loadRegistry();
  for (const e of Object.values(reg)) {
    if (e.port) used.add(e.port);
  }
  return used;
}

async function waitHealth(port: number, healthPath: string, timeoutMs = 30_000): Promise<void> {
  const path = healthPath.startsWith('/') ? healthPath : `/${healthPath}`;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}${path}`, { signal: AbortSignal.timeout(3000) });
      if (r.ok) return;
    } catch {
      /* retry */
    }
    await delay(500);
  }
  throw new Error(`健康检查超时：${path}`);
}

export async function startProject(slug: string): Promise<ProjectSummary> {
  const manifest = readManifest(slug);
  if (manifest.type === 'static') {
    return getProject(slug);
  }

  const existing = runtimes.get(slug);
  if (existing?.proc && existing.status === 'running') {
    return getProject(slug);
  }

  const backend = manifest.backend ?? { command: 'node index.mjs', cwd: 'server', healthPath: '/health' };
  const dir = projectDir(slug);
  const cwd = resolve(dir, backend.cwd || 'server');
  if (!existsSync(cwd)) {
    throw new Error(`backend 目录不存在：${backend.cwd}`);
  }

  const port = backend.port ?? pickPort(collectUsedPorts());
  runtimes.set(slug, { status: 'starting', port });

  const env = {
    ...process.env,
    PORT: String(port),
    NODE_ENV: process.env.NODE_ENV || 'production',
    ...(manifest.env ?? {}),
  };

  const parts = backend.command.trim().split(/\s+/);
  const cmd = parts[0]!;
  const args = parts.slice(1);

  if (existsSync(join(cwd, 'package.json'))) {
    try {
      await new Promise<void>((res, rej) => {
        const inst = spawn('npm', ['install', '--omit=dev'], { cwd, env, stdio: 'ignore' });
        inst.on('exit', (code) => (code === 0 ? res() : rej(new Error(`npm install 失败 ${code}`))));
      });
    } catch {
      /* optional */
    }
  }

  const proc = spawn(cmd, args, { cwd, env, stdio: 'pipe', detached: false });
  const rt = runtimes.get(slug)!;
  rt.proc = proc;

  proc.on('exit', (code) => {
    rt.status = 'stopped';
    rt.error = code && code !== 0 ? `进程退出 code=${code}` : undefined;
    const reg = loadRegistry();
    reg[slug] = { ...reg[slug], status: rt.status, error: rt.error, pid: undefined };
    saveRegistry(reg);
  });

  proc.stderr?.on('data', (c) => {
    rt.error = c.toString().slice(-500);
  });

  try {
    await waitHealth(port, backend.healthPath || '/health');
    rt.status = 'running';
    rt.error = undefined;
  } catch (err) {
    rt.status = 'error';
    rt.error = err instanceof Error ? err.message : String(err);
    try {
      proc.kill('SIGTERM');
    } catch {
      /* ignore */
    }
  }

  const reg = loadRegistry();
  reg[slug] = {
    port,
    pid: proc.pid,
    status: rt.status,
    error: rt.error,
    startedAt: new Date().toISOString(),
  };
  saveRegistry(reg);

  return getProject(slug);
}

export async function stopProject(slug: string): Promise<ProjectSummary> {
  readManifest(slug);
  const rt = runtimes.get(slug);
  if (rt?.proc) {
    rt.proc.kill('SIGTERM');
    await delay(300);
    runtimes.delete(slug);
  }
  const reg = loadRegistry();
  delete reg[slug];
  saveRegistry(reg);
  return getProject(slug);
}

export async function restartProject(slug: string): Promise<ProjectSummary> {
  await stopProject(slug);
  const manifest = readManifest(slug);
  if (manifest.type === 'static') return getProject(slug);
  return startProject(slug);
}

export async function deleteProject(slug: string): Promise<void> {
  await stopProject(slug).catch(() => undefined);
  const dir = projectDir(slug);
  rmSync(dir, { recursive: true, force: true });
  const reg = loadRegistry();
  delete reg[slug];
  saveRegistry(reg);
}

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

export function resolvePublicFile(slug: string, subPath: string): { filePath: string; mime: string } {
  readManifest(slug);
  const dir = projectDir(slug);
  const publicDir = resolve(dir, 'public');
  const safe = normalize(subPath).replace(/^(\.\.(\/|\\|$))+/, '');
  const filePath = resolve(publicDir, safe);
  if (!filePath.startsWith(publicDir + '/') && filePath !== publicDir) {
    throw new Error('路径非法');
  }
  let target = filePath;
  if (existsSync(target) && statSync(target).isDirectory()) {
    target = join(target, 'index.html');
  }
  if (!existsSync(target) || !statSync(target).isFile()) {
    target = join(publicDir, 'index.html');
  }
  if (!existsSync(target)) {
    throw new Error('找不到前端入口');
  }
  const mime = MIME[extname(target).toLowerCase()] ?? 'application/octet-stream';
  return { filePath: target, mime };
}

function resolvePublicWritePath(slug: string, subPath: string): string {
  readManifest(slug);
  const publicDir = resolve(projectDir(slug), 'public');
  const safe = normalize(subPath || 'index.html').replace(/^(\.\.(\/|\\|$))+/, '');
  const filePath = resolve(publicDir, safe);
  if (!filePath.startsWith(publicDir + '/') && filePath !== publicDir) {
    throw new Error('路径非法');
  }
  return filePath;
}

/** 写入 static 项目 public/ 下文件（运维/同步示例用） */
export function writePublicFile(slug: string, subPath: string, content: string): void {
  const filePath = resolvePublicWritePath(slug, subPath);
  mkdirSync(join(filePath, '..'), { recursive: true });
  writeFileSync(filePath, content, 'utf8');
}

export async function proxyProjectApi(
  slug: string,
  apiPath: string,
  init: RequestInit,
): Promise<Response> {
  const manifest = readManifest(slug);
  if (manifest.type === 'static') {
    return new Response(JSON.stringify({ message: '静态项目无 API 后端' }), { status: 404 });
  }
  const rt = getRuntimeState(slug);
  if (rt.status !== 'running' || !rt.port) {
    return new Response(JSON.stringify({ message: '项目未启动，请先在 App 或 API 启动' }), { status: 503 });
  }
  const path = apiPath.startsWith('/') ? apiPath : `/${apiPath}`;
  const url = `http://127.0.0.1:${rt.port}${path}`;
  return fetch(url, init);
}

/** Gateway 启动时清理孤儿 registry（不自动拉起进程） */
export function reconcileProjectRegistryOnBoot(): void {
  const reg = loadRegistry();
  const cleaned: RegistryFile = {};
  for (const [slug, entry] of Object.entries(reg)) {
    if (entry.pid) {
      try {
        process.kill(entry.pid, 0);
        cleaned[slug] = { ...entry, status: 'stopped' };
      } catch {
        /* dead pid */
      }
    }
  }
  saveRegistry(cleaned);
}

export function scanProjectSlugFromDirname(name: string): boolean {
  return /^[a-z0-9][a-z0-9_-]{0,63}$/.test(name);
}

export function relativePublicPath(slug: string, requestPath: string): string {
  const prefix = `/v1/projects/${slug}/`;
  let sub = requestPath;
  if (sub.startsWith(prefix)) sub = sub.slice(prefix.length);
  sub = sub.replace(/^\//, '');
  if (!sub) sub = 'index.html';
  return sub;
}
