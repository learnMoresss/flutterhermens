import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { hermesPath } from './agent-home.js';

export interface InstalledSkill {
  name: string;
  category: string;
  description: string;
  id?: string;
  path?: string;
}

export interface BundledSkill {
  name: string;
  category: string;
  description: string;
  source: string;
  installed: boolean;
  id: string;
}

function parseSkillFrontmatter(content: string): { name: string; description: string } {
  const result = { name: '', description: '' };
  if (!content.startsWith('---')) {
    const headingMatch = content.match(/^#\s+(.+)/m);
    if (headingMatch) result.name = headingMatch[1].trim();
    const paraMatch = content.match(/^(?!#)(?!---).+/m);
    if (paraMatch) result.description = paraMatch[0].trim().slice(0, 120);
    return result;
  }
  const endIdx = content.indexOf('---', 3);
  if (endIdx === -1) return result;
  const frontmatter = content.slice(3, endIdx);
  const nameMatch = frontmatter.match(/^\s*name:\s*["']?([^"'\n]+)["']?\s*$/m);
  if (nameMatch) result.name = nameMatch[1].trim();
  const descMatch = frontmatter.match(/^\s*description:\s*["']?([^"'\n]+)["']?\s*$/m);
  if (descMatch) result.description = descMatch[1].trim();
  return result;
}

export function listInstalledSkills(): InstalledSkill[] {
  const skillsDir = hermesPath('skills');
  if (!existsSync(skillsDir)) return [];

  const skills: InstalledSkill[] = [];
  try {
    for (const category of readdirSync(skillsDir)) {
      const categoryPath = join(skillsDir, category);
      if (!statSync(categoryPath).isDirectory()) continue;
      for (const entry of readdirSync(categoryPath)) {
        const entryPath = join(categoryPath, entry);
        if (!statSync(entryPath).isDirectory()) continue;
        const skillFile = join(entryPath, 'SKILL.md');
        if (!existsSync(skillFile)) continue;
        try {
          const content = readFileSync(skillFile, 'utf-8').slice(0, 4000);
          const meta = parseSkillFrontmatter(content);
          skills.push({
            name: meta.name || entry,
            category,
            description: meta.description || '',
            id: `${category}/${entry}`,
            path: entryPath,
          });
        } catch {
          skills.push({ name: entry, category, description: '' });
        }
      }
    }
  } catch {
    return [];
  }
  return skills.sort(
    (a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name),
  );
}

function bundledSkillsDir(): string {
  const repo = process.env.HERMES_REPO?.trim();
  if (repo) return join(repo, 'skills');
  return join(hermesPath('hermes-agent'), 'skills');
}

export function listBundledSkills(): BundledSkill[] {
  const bundledDir = bundledSkillsDir();
  if (!existsSync(bundledDir)) return [];
  const installed = new Set(listInstalledSkills().map((s) => `${s.category}/${s.name}`));
  const skills: BundledSkill[] = [];
  try {
    for (const category of readdirSync(bundledDir)) {
      const categoryPath = join(bundledDir, category);
      if (!statSync(categoryPath).isDirectory()) continue;
      for (const entry of readdirSync(categoryPath)) {
        const entryPath = join(categoryPath, entry);
        if (!statSync(entryPath).isDirectory()) continue;
        const skillFile = join(entryPath, 'SKILL.md');
        if (!existsSync(skillFile)) continue;
        const content = readFileSync(skillFile, 'utf-8').slice(0, 4000);
        const meta = parseSkillFrontmatter(content);
        const id = `${category}/${entry}`;
        skills.push({
          name: meta.name || entry,
          category,
          description: meta.description || '',
          source: 'bundled',
          installed: installed.has(id) || installed.has(`${category}/${meta.name || entry}`),
          id,
        });
      }
    }
  } catch {
    return [];
  }
  return skills.sort(
    (a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name),
  );
}

export function getSkillContentById(skillId: string): string {
  const parts = skillId.split('/');
  if (parts.length < 2) return '';
  const category = parts[0];
  const entry = parts.slice(1).join('/');
  const skillFile = join(hermesPath('skills', category, entry, 'SKILL.md'));
  if (!existsSync(skillFile)) return '';
  try {
    return readFileSync(skillFile, 'utf-8');
  } catch {
    return '';
  }
}

export async function installSkillViaCli(identifier: string): Promise<{ ok: boolean; error?: string }> {
  const { runHermesCli } = await import('./hermes-cli.js');
  const r = await runHermesCli(['skills', 'install', identifier, '--yes'], 120_000);
  if (r.code !== 0) return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '安装失败' };
  return { ok: true };
}

export async function uninstallSkillViaCli(name: string): Promise<{ ok: boolean; error?: string }> {
  const { runHermesCli } = await import('./hermes-cli.js');
  const r = await runHermesCli(['skills', 'uninstall', name, '--yes'], 60_000);
  if (r.code !== 0) return { ok: false, error: r.stderr.trim() || r.stdout.trim() || '卸载失败' };
  return { ok: true };
}
