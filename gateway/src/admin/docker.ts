import { spawn } from 'node:child_process';

const CONTAINER_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/;
const CONTAINER_NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/;
const IMAGE_REF_RE = /^[a-zA-Z0-9][a-zA-Z0-9@:./_-]{0,255}$/;

export type DockerContainerSummary = {
  id: string;
  name: string;
  image: string;
  status: string;
  state: string;
  ports: string;
  composeProject: string | null;
  createdAt: string | null;
  labels: string | null;
};

export type DockerImageSummary = {
  id: string;
  repository: string;
  tag: string;
  size: string;
  createdAt: string | null;
};

export type DockerContainerStats = {
  cpuPercent: string;
  memUsage: string;
  memPercent: string;
  netIO: string;
  blockIO: string;
};

export type ListContainersQuery = {
  search?: string;
  state?: string;
  project?: string;
};

function assertContainerId(id: string): string {
  const trimmed = id.trim();
  if (!CONTAINER_ID_RE.test(trimmed)) {
    throw new Error('无效的容器 ID');
  }
  return trimmed;
}

function assertContainerName(name: string): string {
  const trimmed = name.trim().replace(/^\//, '');
  if (!CONTAINER_NAME_RE.test(trimmed)) {
    throw new Error('无效的容器名称（仅允许字母数字、_、.、-）');
  }
  return trimmed;
}

function assertImageRef(ref: string): string {
  const trimmed = ref.trim();
  if (!IMAGE_REF_RE.test(trimmed)) {
    throw new Error('无效的镜像引用');
  }
  return trimmed;
}

async function runDocker(args: string[], timeoutMs = 60_000): Promise<{ code: number; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env,
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
      reject(new Error(`docker 命令超时 ${timeoutMs}ms`));
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

function parseJsonLines<T>(raw: string): T[] {
  const out: T[] = [];
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try {
      out.push(JSON.parse(t) as T);
    } catch {
      /* skip malformed line */
    }
  }
  return out;
}

function mapContainer(row: Record<string, unknown>): DockerContainerSummary {
  const labelsRaw = row.Labels;
  let composeProject: string | null = null;
  let labels: string | null = null;
  if (typeof labelsRaw === 'string' && labelsRaw.length > 0) {
    labels = labelsRaw;
    for (const part of labelsRaw.split(',')) {
      const [k, v] = part.split('=');
      if (k === 'com.docker.compose.project' && v) {
        composeProject = v;
        break;
      }
    }
  }
  const names = String(row.Names ?? row.names ?? '');
  const name = names.replace(/^\//, '').split(',')[0] ?? names;
  return {
    id: String(row.ID ?? row.Id ?? ''),
    name,
    image: String(row.Image ?? row.image ?? ''),
    status: String(row.Status ?? row.status ?? ''),
    state: String(row.State ?? row.state ?? ''),
    ports: String(row.Ports ?? row.ports ?? ''),
    composeProject,
    createdAt: row.CreatedAt != null ? String(row.CreatedAt) : null,
    labels,
  };
}

function filterContainers(list: DockerContainerSummary[], query?: ListContainersQuery): DockerContainerSummary[] {
  if (!query) return list;
  const search = query.search?.trim().toLowerCase();
  const state = query.state?.trim().toLowerCase();
  const project = query.project?.trim();
  return list.filter((c) => {
    if (state && state !== 'all') {
      if (state === 'running' && c.state.toLowerCase() !== 'running') return false;
      if (state === 'stopped' && c.state.toLowerCase() === 'running') return false;
      if (state === 'paused' && !c.status.toLowerCase().includes('paused')) return false;
    }
    if (project && project !== 'all' && c.composeProject !== project) return false;
    if (search) {
      const hay = `${c.name} ${c.image} ${c.id} ${c.composeProject ?? ''} ${c.ports}`.toLowerCase();
      if (!hay.includes(search)) return false;
    }
    return true;
  });
}

export async function listDockerContainers(query?: ListContainersQuery): Promise<DockerContainerSummary[]> {
  const r = await runDocker(['ps', '-a', '--format', '{{json .}}']);
  if (r.code !== 0) {
    throw new Error(r.stderr.trim() || r.stdout.trim() || 'docker ps 失败');
  }
  const list = parseJsonLines<Record<string, unknown>>(r.stdout).map(mapContainer);
  return filterContainers(list, query);
}

export async function inspectDockerContainer(id: string): Promise<Record<string, unknown>> {
  const cid = assertContainerId(id);
  const r = await runDocker(['inspect', cid, '--format', '{{json .}}']);
  if (r.code !== 0) {
    throw new Error(r.stderr.trim() || 'docker inspect 失败');
  }
  const parsed = JSON.parse(r.stdout.trim()) as Record<string, unknown>;
  return parsed;
}

export async function dockerContainerStart(id: string): Promise<void> {
  const cid = assertContainerId(id);
  const r = await runDocker(['start', cid]);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker start 失败');
}

export async function dockerContainerStop(id: string): Promise<void> {
  const cid = assertContainerId(id);
  const r = await runDocker(['stop', cid], 120_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker stop 失败');
}

export async function dockerContainerRestart(id: string): Promise<void> {
  const cid = assertContainerId(id);
  const r = await runDocker(['restart', cid], 120_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker restart 失败');
}

export async function dockerContainerPause(id: string): Promise<void> {
  const cid = assertContainerId(id);
  const r = await runDocker(['pause', cid]);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker pause 失败');
}

export async function dockerContainerUnpause(id: string): Promise<void> {
  const cid = assertContainerId(id);
  const r = await runDocker(['unpause', cid]);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker unpause 失败');
}

export async function dockerContainerRename(id: string, newName: string): Promise<void> {
  const cid = assertContainerId(id);
  const name = assertContainerName(newName);
  const r = await runDocker(['rename', cid, name]);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker rename 失败');
}

export async function dockerContainerRemove(id: string, force = false): Promise<void> {
  const cid = assertContainerId(id);
  const args = ['rm'];
  if (force) args.push('-f');
  args.push(cid);
  const r = await runDocker(args, 120_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker rm 失败');
}

export async function dockerContainerLogs(id: string, tail = 200): Promise<string> {
  const cid = assertContainerId(id);
  const n = Math.min(Math.max(Math.floor(tail), 1), 2000);
  const r = await runDocker(['logs', '--tail', String(n), cid], 120_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker logs 失败');
  return r.stdout + (r.stderr ? `\n${r.stderr}` : '');
}

export async function dockerContainerStats(id: string): Promise<DockerContainerStats> {
  const cid = assertContainerId(id);
  const r = await runDocker(['stats', '--no-stream', '--format', '{{json .}}', cid], 30_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker stats 失败');
  const row = parseJsonLines<Record<string, unknown>>(r.stdout)[0] ?? {};
  return {
    cpuPercent: String(row.CPUPerc ?? row.CPU ?? ''),
    memUsage: String(row.MemUsage ?? ''),
    memPercent: String(row.MemPerc ?? ''),
    netIO: String(row.NetIO ?? ''),
    blockIO: String(row.BlockIO ?? ''),
  };
}

function mapImage(row: Record<string, unknown>): DockerImageSummary {
  const repo = String(row.Repository ?? '');
  const tag = String(row.Tag ?? '');
  return {
    id: String(row.ID ?? row.Id ?? ''),
    repository: repo,
    tag,
    size: String(row.Size ?? ''),
    createdAt: row.CreatedAt != null ? String(row.CreatedAt) : null,
  };
}

export async function listDockerImages(): Promise<DockerImageSummary[]> {
  const r = await runDocker(['images', '--format', '{{json .}}']);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker images 失败');
  return parseJsonLines<Record<string, unknown>>(r.stdout).map(mapImage);
}

export async function dockerImageRemove(ref: string, force = false): Promise<void> {
  const imageRef = assertImageRef(ref);
  const args = ['rmi'];
  if (force) args.push('-f');
  args.push(imageRef);
  const r = await runDocker(args, 120_000);
  if (r.code !== 0) throw new Error(r.stderr.trim() || 'docker rmi 失败');
}

export async function dockerPrune(targets: ('containers' | 'images')[]): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  const unique = [...new Set(targets)];
  for (const t of unique) {
    if (t === 'containers') {
      const r = await runDocker(['container', 'prune', '-f'], 120_000);
      if (r.code !== 0) throw new Error(r.stderr.trim() || 'container prune 失败');
      out.containers = (r.stdout + r.stderr).trim() || '完成';
    }
    if (t === 'images') {
      const r = await runDocker(['image', 'prune', '-f'], 120_000);
      if (r.code !== 0) throw new Error(r.stderr.trim() || 'image prune 失败');
      out.images = (r.stdout + r.stderr).trim() || '完成';
    }
  }
  return out;
}

export async function probeDockerAvailable(): Promise<boolean> {
  try {
    const r = await runDocker(['info', '--format', '{{.ServerVersion}}'], 8000);
    return r.code === 0;
  } catch {
    return false;
  }
}
