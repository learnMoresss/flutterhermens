import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

import { getHermesHome } from './agent-home.js';

export interface SavedModel {
  id: string;
  name: string;
  provider: string;
  model: string;
  baseUrl: string;
  apiMode?: string | null;
  createdAt?: number;
}

export { getHermesHome };

export function listSavedModels(): SavedModel[] {
  const file = join(getHermesHome(), 'models.json');
  if (!existsSync(file)) return [];
  try {
    const parsed = JSON.parse(readFileSync(file, 'utf-8')) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((m): m is Record<string, unknown> => m != null && typeof m === 'object')
      .map((m) => ({
        id: String(m.id ?? m.model ?? ''),
        name: String(m.name ?? m.model ?? '未命名'),
        provider: String(m.provider ?? ''),
        model: String(m.model ?? ''),
        baseUrl: String(m.baseUrl ?? ''),
        apiMode: m.apiMode == null ? null : String(m.apiMode),
        createdAt: typeof m.createdAt === 'number' ? m.createdAt : undefined,
      }))
      .filter((m) => m.model.length > 0);
  } catch {
    return [];
  }
}

function modelsFile(): string {
  return join(getHermesHome(), 'models.json');
}

function writeModels(models: SavedModel[]): void {
  writeFileSync(modelsFile(), JSON.stringify(models, null, 2), 'utf-8');
}

export function addSavedModel(
  name: string,
  provider: string,
  model: string,
  baseUrl: string,
): SavedModel {
  const models = listSavedModels();
  const existing = models.find((m) => m.model === model && m.provider === provider);
  if (existing) return existing;
  const entry: SavedModel = {
    id: randomUUID(),
    name,
    provider,
    model,
    baseUrl: baseUrl || '',
    createdAt: Date.now(),
  };
  models.push(entry);
  writeModels(models);
  return entry;
}

export function removeSavedModel(id: string): boolean {
  const models = listSavedModels();
  const filtered = models.filter((m) => m.id !== id);
  if (filtered.length === models.length) return false;
  writeModels(filtered);
  return true;
}

export function updateSavedModel(
  id: string,
  fields: Partial<Pick<SavedModel, 'name' | 'provider' | 'model' | 'baseUrl'>>,
): boolean {
  const models = listSavedModels();
  const idx = models.findIndex((m) => m.id === id);
  if (idx === -1) return false;
  models[idx] = { ...models[idx], ...fields };
  writeModels(models);
  return true;
}
