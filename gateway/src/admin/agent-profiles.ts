import { existsSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { getHermesHome, hermesPath, parseConfigField, readTextFile } from './agent-home.js';

export interface ProfileInfo {
  name: string;
  isDefault: boolean;
  isActive: boolean;
  model: string;
  provider: string;
  hasEnv: boolean;
  hasSoul: boolean;
  skillCount: number;
}

function readProfileConfig(profilePath: string): { model: string; provider: string } {
  const configFile = join(profilePath, 'config.yaml');
  if (!existsSync(configFile)) return { model: '', provider: '' };
  const content = readTextFile(configFile);
  return {
    model: parseConfigField(content, 'default'),
    provider: parseConfigField(content, 'provider') || 'auto',
  };
}

function countSkills(profilePath: string): number {
  const skillsDir = join(profilePath, 'skills');
  if (!existsSync(skillsDir)) return 0;
  let count = 0;
  try {
    for (const d of readdirSync(skillsDir)) {
      const sub = join(skillsDir, d);
      if (!statSync(sub).isDirectory()) continue;
      for (const f of readdirSync(sub)) {
        if (existsSync(join(sub, f, 'SKILL.md'))) count++;
      }
    }
  } catch {
    return 0;
  }
  return count;
}

function getActiveProfileName(): string {
  const activeFile = hermesPath('active_profile');
  if (!existsSync(activeFile)) return 'default';
  const name = readTextFile(activeFile).trim();
  return name || 'default';
}

export function listProfiles(): ProfileInfo[] {
  const home = getHermesHome();
  const activeName = getActiveProfileName();
  const profiles: ProfileInfo[] = [];

  const defaultConfig = readProfileConfig(home);
  profiles.push({
    name: 'default',
    isDefault: true,
    isActive: activeName === 'default',
    model: defaultConfig.model,
    provider: defaultConfig.provider,
    hasEnv: existsSync(join(home, '.env')),
    hasSoul: existsSync(join(home, 'SOUL.md')),
    skillCount: countSkills(home),
  });

  const profilesDir = join(home, 'profiles');
  if (existsSync(profilesDir)) {
    for (const name of readdirSync(profilesDir)) {
      if (name.startsWith('.')) continue;
      const profilePath = join(profilesDir, name);
      if (!statSync(profilePath).isDirectory()) continue;
      const config = readProfileConfig(profilePath);
      profiles.push({
        name,
        isDefault: false,
        isActive: activeName === name,
        model: config.model,
        provider: config.provider,
        hasEnv: existsSync(join(profilePath, '.env')),
        hasSoul: existsSync(join(profilePath, 'SOUL.md')),
        skillCount: countSkills(profilePath),
      });
    }
  }
  return profiles;
}

export function setActiveProfile(name: string): void {
  if (!/^[\w-]+$/.test(name)) {
    throw new Error('无效的档案名称');
  }
  writeFileSync(hermesPath('active_profile'), `${name}\n`, 'utf-8');
}

export async function createProfileViaCli(
  name: string,
  clone: boolean,
): Promise<{ ok: boolean; error?: string }> {
  if (name === 'default') return { ok: false, error: '不能创建 default 档案' };
  if (!/^[\w-]+$/.test(name)) return { ok: false, error: '档案名称仅允许字母、数字、下划线与连字符' };
  const { runHermesCli } = await import('./hermes-cli.js');
  const args = clone ? ['profile', 'create', name, '--clone'] : ['profile', 'create', name];
  const r = await runHermesCli(args, 30_000);
  if (r.code !== 0) return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '创建失败' };
  return { ok: true };
}

export async function deleteProfileViaCli(name: string): Promise<{ ok: boolean; error?: string }> {
  if (name === 'default') return { ok: false, error: '不能删除 default 档案' };
  if (!/^[\w-]+$/.test(name)) return { ok: false, error: '无效的档案名称' };
  const { runHermesCli } = await import('./hermes-cli.js');
  const r = await runHermesCli(['profile', 'delete', name, '--yes'], 30_000);
  if (r.code !== 0) return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '删除失败' };
  return { ok: true };
}
