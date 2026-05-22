import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  createReadStream,
  existsSync,
  readdirSync,
  realpathSync,
  statSync,
  type Dirent,
  type Stats,
} from 'node:fs';
import { basename, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ReadStream } from 'node:fs';

import { loadConfig } from '../config.js';

const IMAGE_EXTS = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.svg',
  '.bmp',
  '.ico',
  '.avif',
]);

const MIME_BY_EXT: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.bmp': 'image/bmp',
  '.ico': 'image/x-icon',
  '.avif': 'image/avif',
  '.md': 'text/markdown; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.pdf': 'application/pdf',
  '.zip': 'application/zip',
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.csv': 'text/csv; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.mp4': 'video/mp4',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
};

export function getMediaRoots(): string[] {
  const raw = process.env.GATEWAY_MEDIA_ROOTS?.trim();
  const list = raw
    ? raw.split(',').map((s) => s.trim()).filter(Boolean)
    : ['/tmp', '/home/ubuntu/.hermes', '/data/gateway-uploads'];
  return list.map((p) => {
    try {
      return realpathSync(p);
    } catch {
      return p;
    }
  });
}

export function getPublicBaseUrl(): string {
  const raw = process.env.GATEWAY_PUBLIC_BASE_URL?.trim();
  if (!raw) return '';
  return raw.endsWith('/') ? raw.slice(0, -1) : raw;
}

/** Hermes 跑在宿主机时用此地址拉取 Gateway 上传文件（避免公网 IP  hairpin 失败） */
export function getInternalBaseUrl(): string {
  const raw = process.env.GATEWAY_INTERNAL_BASE_URL?.trim();
  const base = raw || 'http://127.0.0.1:3000';
  return base.endsWith('/') ? base.slice(0, -1) : base;
}

export function getMediaTokenTtlSec(): number {
  const raw = process.env.GATEWAY_MEDIA_TOKEN_TTL_SEC?.trim();
  const n = raw ? Number.parseInt(raw, 10) : 604_800;
  return Number.isFinite(n) && n >= 60 ? n : 604_800;
}

function signingSecret(): string {
  return loadConfig().JWT_SECRET;
}

export function signAccessToken(resource: string, exp: number): string {
  return createHmac('sha256', signingSecret())
    .update(`${resource}\0${exp}`)
    .digest('hex');
}

export function verifyAccessToken(resource: string, exp: number, sig: string): boolean {
  if (!sig || !Number.isFinite(exp)) return false;
  if (exp < Math.floor(Date.now() / 1000)) return false;
  const expected = signAccessToken(resource, exp);
  try {
    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(sig, 'hex');
    return a.length === b.length && timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

export function createAccessQuery(resource: string): { exp: number; sig: string } {
  const exp = Math.floor(Date.now() / 1000) + getMediaTokenTtlSec();
  const sig = signAccessToken(resource, exp);
  return { exp, sig };
}

export function encodePathParam(absPath: string): string {
  return Buffer.from(absPath, 'utf-8').toString('base64url');
}

export function decodePathParam(encoded: string): string | null {
  const trimmed = encoded.trim();
  if (!trimmed) return null;

  // Fastify 已 URL 解码：?path=/home/ubuntu/...（非 base64）
  if (trimmed.startsWith('/')) {
    return trimmed;
  }

  if (trimmed.toLowerCase().startsWith('file://')) {
    try {
      return fileURLToPath(trimmed);
    } catch {
      return null;
    }
  }

  try {
    return Buffer.from(trimmed, 'base64url').toString('utf-8');
  } catch {
    /* fall through */
  }

  try {
    let b64 = trimmed.replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4;
    if (pad) b64 += '='.repeat(4 - pad);
    return Buffer.from(b64, 'base64').toString('utf-8');
  } catch {
    return null;
  }
}

export function isPathAllowed(absPath: string): boolean {
  let resolved: string;
  try {
    resolved = realpathSync(absPath);
  } catch {
    return false;
  }
  const roots = getMediaRoots();
  return roots.some((root) => resolved === root || resolved.startsWith(`${root}/`));
}

export function resolveReadableFile(absPath: string): { path: string; stat: Stats } | null {
  if (!isPathAllowed(absPath)) return null;
  let resolved: string;
  try {
    resolved = realpathSync(absPath);
  } catch {
    return null;
  }
  if (!existsSync(resolved)) return null;
  let stat: ReturnType<typeof statSync>;
  try {
    stat = statSync(resolved);
  } catch {
    return null;
  }
  if (!stat.isFile()) return null;
  return { path: resolved, stat };
}

export function guessMimeType(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  return MIME_BY_EXT[ext] ?? 'application/octet-stream';
}

export function isImagePath(filePath: string): boolean {
  return IMAGE_EXTS.has(extname(filePath).toLowerCase());
}

const VIDEO_EXTS = new Set(['.mp4', '.webm', '.mov', '.m4v', '.mkv']);

export function isVideoPath(filePath: string): boolean {
  return VIDEO_EXTS.has(extname(filePath).toLowerCase());
}

/** MEDIA:final_video.mp4 或 MEDIA:subdir/x.mp4 → 媒体根下绝对路径 */
export function resolveBareMediaName(name: string): string | null {
  const trimmed = name.trim();
  if (!trimmed || trimmed.includes('..')) return null;

  for (const root of getMediaRoots()) {
    const candidate = join(root, trimmed);
    if (!existsSync(candidate)) continue;
    try {
      const resolved = realpathSync(candidate);
      if (isPathAllowed(resolved)) return resolved;
    } catch {
      if (isPathAllowed(candidate)) return candidate;
    }
  }

  if (!trimmed.includes('/')) {
    for (const root of getMediaRoots()) {
      const found = findFileByBasename(root, trimmed, 0, 8);
      if (found) return found;
    }
  }
  return null;
}

function findFileByBasename(dir: string, fileName: string, depth: number, maxDepth: number): string | null {
  if (depth > maxDepth) return null;
  let entries: Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return null;
  }
  for (const ent of entries) {
    if (ent.name.startsWith('.')) continue;
    const full = join(dir, ent.name);
    if (ent.isFile() && ent.name === fileName) {
      try {
        const resolved = realpathSync(full);
        return isPathAllowed(resolved) ? resolved : null;
      } catch {
        return isPathAllowed(full) ? full : null;
      }
    }
    if (ent.isDirectory()) {
      const hit = findFileByBasename(full, fileName, depth + 1, maxDepth);
      if (hit) return hit;
    }
  }
  return null;
}

export function buildMediaServeUrl(absPath: string): string | null {
  const base = getPublicBaseUrl();
  if (!base) return null;
  let resolved: string;
  try {
    resolved = realpathSync(absPath);
  } catch {
    resolved = absPath;
  }
  if (!isPathAllowed(resolved)) return null;
  const { exp, sig } = createAccessQuery(resolved);
  const pathParam = encodePathParam(resolved);
  const qs = new URLSearchParams({ path: pathParam, exp: String(exp), sig });
  return `${base}/v1/media/serve?${qs.toString()}`;
}

export function buildUploadFileUrl(fileId: string, baseUrl?: string): string | null {
  const base = (baseUrl?.trim() || getPublicBaseUrl()).replace(/\/$/, '');
  if (!base) return null;
  const resource = `upload:${fileId}`;
  const { exp, sig } = createAccessQuery(resource);
  const qs = new URLSearchParams({ access: sig, exp: String(exp) });
  return `${base}/v1/files/${encodeURIComponent(fileId)}?${qs.toString()}`;
}

export function verifyUploadAccess(fileId: string, exp: number, access: string): boolean {
  return verifyAccessToken(`upload:${fileId}`, exp, access);
}

export function openFileStream(absPath: string): ReadStream | null {
  const info = resolveReadableFile(absPath);
  if (!info) return null;
  return createReadStream(info.path);
}

export function fileDisplayName(absPath: string): string {
  return basename(absPath);
}
