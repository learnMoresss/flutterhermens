import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { getHermesRepo } from './hermes-cli.js';
import { hermesPath, writeTextFile } from './agent-home.js';

const ENTRY_DELIMITER = '\n§\n';
const MEMORY_CHAR_LIMIT = 2200;
const USER_CHAR_LIMIT = 1375;

export interface MemoryEntry {
  index: number;
  content: string;
}

export interface MemoryInfo {
  memory: {
    content: string;
    exists: boolean;
    lastModified: number | null;
    entries: MemoryEntry[];
    charCount: number;
    charLimit: number;
  };
  user: {
    content: string;
    exists: boolean;
    lastModified: number | null;
    charCount: number;
    charLimit: number;
  };
  stats: { totalSessions: number; totalMessages: number };
}

function memoryPath(): string {
  return hermesPath('memories', 'MEMORY.md');
}

function userPath(): string {
  return hermesPath('memories', 'USER.md');
}

function readFileSafe(filePath: string): {
  content: string;
  exists: boolean;
  lastModified: number | null;
} {
  if (!existsSync(filePath)) {
    return { content: '', exists: false, lastModified: null };
  }
  try {
    const content = readFileSync(filePath, 'utf-8');
    const stat = statSync(filePath);
    return {
      content,
      exists: true,
      lastModified: Math.floor(stat.mtimeMs / 1000),
    };
  } catch {
    return { content: '', exists: false, lastModified: null };
  }
}

function parseMemoryEntries(content: string): MemoryEntry[] {
  if (!content.trim()) return [];
  return content
    .split(ENTRY_DELIMITER)
    .map((entry, index) => ({ index, content: entry.trim() }))
    .filter((e) => e.content.length > 0);
}

function serializeEntries(entries: MemoryEntry[]): string {
  return entries.map((e) => e.content).join(ENTRY_DELIMITER);
}

function getSessionStats(): { totalSessions: number; totalMessages: number } {
  const dbPath = hermesPath('state.db');
  if (!existsSync(dbPath)) return { totalSessions: 0, totalMessages: 0 };
  return { totalSessions: 0, totalMessages: 0 };
}

export function readMemory(): MemoryInfo {
  const memFile = readFileSafe(memoryPath());
  const userFile = readFileSafe(userPath());
  return {
    memory: {
      ...memFile,
      entries: parseMemoryEntries(memFile.content),
      charCount: memFile.content.length,
      charLimit: MEMORY_CHAR_LIMIT,
    },
    user: {
      ...userFile,
      charCount: userFile.content.length,
      charLimit: USER_CHAR_LIMIT,
    },
    stats: getSessionStats(),
  };
}

export function writeMemoryContent(content: string): { ok: boolean; error?: string } {
  if (content.length > MEMORY_CHAR_LIMIT) {
    return { ok: false, error: `超出记忆上限（${content.length}/${MEMORY_CHAR_LIMIT}）` };
  }
  writeTextFile(memoryPath(), content);
  return { ok: true };
}

export function addMemoryEntry(content: string): { ok: boolean; error?: string } {
  const existing = readFileSafe(memoryPath());
  const entries = parseMemoryEntries(existing.content);
  const newContent = serializeEntries([
    ...entries,
    { index: entries.length, content: content.trim() },
  ]);
  if (newContent.length > MEMORY_CHAR_LIMIT) {
    return { ok: false, error: `超出记忆上限（${newContent.length}/${MEMORY_CHAR_LIMIT}）` };
  }
  writeTextFile(memoryPath(), newContent);
  return { ok: true };
}

export function updateMemoryEntry(index: number, content: string): { ok: boolean; error?: string } {
  const existing = readFileSafe(memoryPath());
  const entries = parseMemoryEntries(existing.content);
  if (index < 0 || index >= entries.length) {
    return { ok: false, error: '条目不存在' };
  }
  entries[index] = { ...entries[index], content: content.trim() };
  const newContent = serializeEntries(entries);
  if (newContent.length > MEMORY_CHAR_LIMIT) {
    return { ok: false, error: `超出记忆上限（${newContent.length}/${MEMORY_CHAR_LIMIT}）` };
  }
  writeTextFile(memoryPath(), newContent);
  return { ok: true };
}

export function removeMemoryEntry(index: number): boolean {
  const existing = readFileSafe(memoryPath());
  const entries = parseMemoryEntries(existing.content);
  if (index < 0 || index >= entries.length) return false;
  entries.splice(index, 1);
  writeTextFile(memoryPath(), serializeEntries(entries));
  return true;
}

export function writeUserProfile(content: string): { ok: boolean; error?: string } {
  if (content.length > USER_CHAR_LIMIT) {
    return { ok: false, error: `超出用户档案上限（${content.length}/${USER_CHAR_LIMIT}）` };
  }
  writeTextFile(userPath(), content);
  return { ok: true };
}

export function discoverMemoryProviders(): Array<{
  name: string;
  description: string;
  installed: boolean;
}> {
  const pluginsDir = join(getHermesRepo(), 'hermes', 'memory');
  if (!existsSync(pluginsDir)) return [];
  const out: Array<{ name: string; description: string; installed: boolean }> = [];
  try {
    for (const name of readdirSync(pluginsDir)) {
      const p = join(pluginsDir, name);
      if (!statSync(p).isDirectory()) continue;
      const initPy = join(p, '__init__.py');
      out.push({
        name,
        description: existsSync(initPy) ? '记忆 Provider 插件' : '',
        installed: existsSync(initPy),
      });
    }
  } catch {
    return [];
  }
  return out;
}
