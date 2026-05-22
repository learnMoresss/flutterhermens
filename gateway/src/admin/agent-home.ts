import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export function getHermesHome(): string {
  const raw = process.env.HERMES_HOME?.trim();
  if (raw) return raw;
  return '/home/ubuntu/.hermes';
}

export function hermesPath(...parts: string[]): string {
  return join(getHermesHome(), ...parts);
}

export function readTextFile(path: string): string {
  if (!existsSync(path)) return '';
  try {
    return readFileSync(path, 'utf-8');
  } catch {
    return '';
  }
}

export function writeTextFile(path: string, content: string): void {
  const dir = join(path, '..');
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(path, content, 'utf-8');
}

export function parseConfigField(content: string, field: string): string {
  const re = new RegExp(`^\\s*${field}:\\s*["']?([^"'\\n#]+)["']?`, 'm');
  const m = content.match(re);
  return m ? m[1].trim() : '';
}
