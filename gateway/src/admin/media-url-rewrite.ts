import { existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildMediaServeUrl,
  getMediaRoots,
  isImagePath,
  isPathAllowed,
  resolveBareMediaName,
} from './media-serve.js';

const FILE_URL_RE = /file:\/\/[^\s\]\)<>\"']+/gi;
const MEDIA_PREFIX_RE = /MEDIA:file:\/\/[^\s\]\)<>\"']+/gi;
/** MEDIA:filename.mp4（无 file://）时在媒体根目录下查找 */
const MEDIA_BARE_RE = /MEDIA:(?!file:\/\/)([^\s\]\)<>\"']+)/gi;

function fileUrlToPath(raw: string): string | null {
  const trimmed = raw.trim();
  const withoutMedia = trimmed.startsWith('MEDIA:') ? trimmed.slice(6) : trimmed;
  if (!withoutMedia.toLowerCase().startsWith('file://')) return null;
  try {
    return fileURLToPath(withoutMedia);
  } catch {
    return null;
  }
}

function buildMarkdownLink(absPath: string): string | null {
  const url = buildMediaServeUrl(absPath);
  if (!url) return null;
  const name = absPath.split('/').pop() ?? 'file';
  if (isImagePath(absPath)) {
    return `![${name}](${url})`;
  }
  return `[${name}](${url})`;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildAbsolutePathPattern(): RegExp | null {
  const roots = getMediaRoots();
  if (roots.length === 0) return null;
  const parts = roots.map((r) => `${escapeRegex(r)}(?:/[^\\s\\]\\)<>\"']+)?`);
  return new RegExp(`(?:^|[\\s(])(${parts.join('|')})`, 'g');
}

function rewriteMatch(raw: string): string {
  const path = fileUrlToPath(raw);
  if (path) {
    const link = buildMarkdownLink(path);
    if (link) return link;
  }
  return raw;
}

function rewriteBareMedia(raw: string): string {
  const name = raw.startsWith('MEDIA:') ? raw.slice(6) : raw;
  const path = resolveBareMediaName(name);
  if (!path) return raw;
  const link = buildMarkdownLink(path);
  return link ?? raw;
}

export function rewriteMediaUrls(text: string): string {
  if (!text) return text;

  let out = text.replace(MEDIA_BARE_RE, (m) => rewriteBareMedia(m));
  out = out.replace(MEDIA_PREFIX_RE, (m) => rewriteMatch(m));
  out = out.replace(FILE_URL_RE, (m) => rewriteMatch(m));

  const absRe = buildAbsolutePathPattern();
  if (absRe) {
    out = out.replace(absRe, (full, captured: string) => {
      if (!captured || !isPathAllowed(captured)) return full;
      const link = buildMarkdownLink(captured);
      if (!link) return full;
      const prefix = full.slice(0, full.length - captured.length);
      return `${prefix}${link}`;
    });
  }

  return out;
}

export function rewriteSseDataLine(line: string): string {
  const trimmed = line.trimEnd();
  if (!trimmed.startsWith('data:')) return line;

  const payload = trimmed.slice(5).trim();
  if (!payload || payload === '[DONE]') return line;

  try {
    const data = JSON.parse(payload) as Record<string, unknown>;
    rewriteJsonContent(data);
    return `data: ${JSON.stringify(data)}`;
  } catch {
    return rewriteMediaUrls(line);
  }
}

function rewriteJsonContent(node: Record<string, unknown>): void {
  const choices = node.choices;
  if (Array.isArray(choices)) {
    for (const choice of choices) {
      if (!choice || typeof choice !== 'object') continue;
      const c = choice as Record<string, unknown>;
      const delta = c.delta;
      if (delta && typeof delta === 'object') {
        const d = delta as Record<string, unknown>;
        if (typeof d.content === 'string') {
          d.content = rewriteMediaUrls(d.content);
        }
      }
      const message = c.message;
      if (message && typeof message === 'object') {
        const m = message as Record<string, unknown>;
        if (typeof m.content === 'string') {
          m.content = rewriteMediaUrls(m.content);
        }
      }
    }
  }

  if (typeof node.content === 'string') {
    node.content = rewriteMediaUrls(node.content);
  }
  if (typeof node.message === 'string') {
    node.message = rewriteMediaUrls(node.message);
  }
  if (typeof node.detail === 'string') {
    node.detail = rewriteMediaUrls(node.detail);
  }
}

export function rewriteJsonResponse(body: unknown): unknown {
  if (typeof body === 'string') return rewriteMediaUrls(body);
  if (!body || typeof body !== 'object') return body;
  const copy = structuredClone(body) as Record<string, unknown>;
  rewriteJsonContent(copy);
  return copy;
}
