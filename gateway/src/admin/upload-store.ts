import { createHash, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export interface StoredUpload {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
  createdAt: string;
}

export function uploadDir(): string {
  const raw = process.env.GATEWAY_UPLOAD_DIR?.trim();
  return raw || join(process.cwd(), 'uploads');
}

export function getUploadFilePath(id: string): string | null {
  const file = dataPath(id);
  return existsSync(file) ? file : null;
}

function metaPath(id: string): string {
  return join(uploadDir(), `${id}.json`);
}

function dataPath(id: string): string {
  return join(uploadDir(), id);
}

function ensureDir(): void {
  const dir = uploadDir();
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

export function saveUpload(
  filename: string,
  mimeType: string,
  buffer: Buffer,
): StoredUpload {
  ensureDir();
  const id = randomUUID();
  const record: StoredUpload = {
    id,
    filename,
    mimeType,
    size: buffer.length,
    createdAt: new Date().toISOString(),
  };
  writeFileSync(dataPath(id), buffer);
  writeFileSync(metaPath(id), JSON.stringify(record, null, 2), 'utf-8');
  return record;
}

export function getUploadMeta(id: string): StoredUpload | null {
  const meta = metaPath(id);
  if (!existsSync(meta)) return null;
  try {
    return JSON.parse(readFileSync(meta, 'utf-8')) as StoredUpload;
  } catch {
    return null;
  }
}

export function readUploadBuffer(id: string): Buffer | null {
  const file = dataPath(id);
  if (!existsSync(file)) return null;
  try {
    return readFileSync(file);
  } catch {
    return null;
  }
}

export function sha256(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}
