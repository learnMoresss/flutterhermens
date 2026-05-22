import { existsSync } from 'node:fs';

import { hermesPath, readTextFile, writeTextFile } from './agent-home.js';

export interface EnvKeyInfo {
  key: string;
  label: string;
  category: string;
  configured: boolean;
  maskedValue: string;
}

const KNOWN_KEYS: { key: string; label: string; category: string }[] = [
  { key: 'OPENROUTER_API_KEY', label: 'OpenRouter', category: '模型提供商' },
  { key: 'ANTHROPIC_API_KEY', label: 'Anthropic', category: '模型提供商' },
  { key: 'OPENAI_API_KEY', label: 'OpenAI', category: '模型提供商' },
  { key: 'GOOGLE_API_KEY', label: 'Google', category: '模型提供商' },
  { key: 'XAI_API_KEY', label: 'xAI', category: '模型提供商' },
  { key: 'API_SERVER_KEY', label: 'API Server 密钥', category: 'Hermes' },
  { key: 'EXA_API_KEY', label: 'Exa 搜索', category: '工具 API' },
  { key: 'TAVILY_API_KEY', label: 'Tavily 搜索', category: '工具 API' },
  { key: 'FIRECRAWL_API_KEY', label: 'Firecrawl', category: '工具 API' },
  { key: 'TELEGRAM_BOT_TOKEN', label: 'Telegram 机器人', category: '网关平台' },
  { key: 'DISCORD_BOT_TOKEN', label: 'Discord 机器人', category: '网关平台' },
  { key: 'SLACK_BOT_TOKEN', label: 'Slack 机器人', category: '网关平台' },
];

function parseEnv(content: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    map.set(key, val);
  }
  return map;
}

function maskValue(val: string): string {
  if (!val) return '';
  if (val.length <= 8) return '***';
  return `${val.slice(0, 4)}…${val.slice(-4)}`;
}

export function listEnvKeys(): EnvKeyInfo[] {
  const envFile = hermesPath('.env');
  const envMap = existsSync(envFile) ? parseEnv(readTextFile(envFile)) : new Map<string, string>();

  const known = KNOWN_KEYS.map((k) => {
    const val = envMap.get(k.key) ?? '';
    return {
      key: k.key,
      label: k.label,
      category: k.category,
      configured: val.length > 0,
      maskedValue: val ? maskValue(val) : '',
    };
  });

  const knownSet = new Set(KNOWN_KEYS.map((k) => k.key));
  for (const [key, val] of envMap) {
    if (knownSet.has(key)) continue;
    if (!key.endsWith('_KEY') && !key.endsWith('_TOKEN') && !key.includes('SECRET')) continue;
    known.push({
      key,
      label: key,
      category: '其他',
      configured: val.length > 0,
      maskedValue: maskValue(val),
    });
  }
  return known;
}

export function getConfigSummary(): { provider: string; model: string; baseUrl: string } {
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) return { provider: '', model: '', baseUrl: '' };
  const content = readTextFile(configFile);
  const providerMatch = content.match(/^\s*provider:\s*["']?([^"'\n#]+)["']?/m);
  const modelMatch = content.match(/^\s*default:\s*["']?([^"'\n#]+)["']?/m);
  const baseUrlMatch = content.match(/^\s*base_url:\s*["']?([^"'\n#]+)["']?/m);
  return {
    provider: providerMatch ? providerMatch[1].trim() : '',
    model: modelMatch ? modelMatch[1].trim() : '',
    baseUrl: baseUrlMatch ? baseUrlMatch[1].trim() : '',
  };
}

const ALLOWED_ENV_KEYS = new Set(KNOWN_KEYS.map((k) => k.key));

export function setEnvKey(key: string, value: string): { ok: boolean; error?: string } {
  if (!ALLOWED_ENV_KEYS.has(key) && !key.endsWith('_KEY') && !key.endsWith('_TOKEN')) {
    return { ok: false, error: '不允许写入该环境变量键' };
  }
  const envFile = hermesPath('.env');
  let content = existsSync(envFile) ? readTextFile(envFile) : '';
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`^${escaped}=.*$`, 'm');
  const line = `${key}=${value}`;
  if (re.test(content)) {
    content = content.replace(re, line);
  } else {
    content = content.trimEnd() + (content.length ? '\n' : '') + `${line}\n`;
  }
  writeTextFile(envFile, content);
  return { ok: true };
}

export function setModelConfig(fields: {
  provider?: string;
  model?: string;
  baseUrl?: string;
}): { ok: boolean; error?: string } {
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) return { ok: false, error: 'config.yaml 不存在' };
  let content = readTextFile(configFile);
  if (fields.provider != null) {
    const re = /^(\s*provider:\s*)(["']?)([^"'\n#]+)(["']?)/m;
    if (re.test(content)) {
      content = content.replace(re, `$1$2${fields.provider}$4`);
    } else {
      content = `provider: ${fields.provider}\n${content}`;
    }
  }
  if (fields.model != null) {
    const re = /^(\s*default:\s*)(["']?)([^"'\n#]+)(["']?)/m;
    if (re.test(content)) {
      content = content.replace(re, `$1$2${fields.model}$4`);
    } else {
      content = `default: ${fields.model}\n${content}`;
    }
  }
  if (fields.baseUrl != null) {
    const re = /^(\s*base_url:\s*)(["']?)([^"'\n#]*)(["']?)/m;
    if (re.test(content)) {
      content = content.replace(re, `$1$2${fields.baseUrl}$4`);
    }
  }
  writeTextFile(configFile, content);
  return { ok: true };
}

const SUPPORTED_PLATFORMS = ['telegram', 'discord', 'slack', 'whatsapp', 'signal'];

export function getPlatformEnabled(): Record<string, boolean> {
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) return {};
  const content = readTextFile(configFile);
  const result: Record<string, boolean> = {};
  for (const platform of SUPPORTED_PLATFORMS) {
    const re = new RegExp(`^[ \\t]+${platform}:\\s*\\n[ \\t]+enabled:\\s*(true|false)`, 'm');
    const match = content.match(re);
    result[platform] = match ? match[1] === 'true' : false;
  }
  return result;
}

export function setPlatformEnabled(platform: string, enabled: boolean): boolean {
  if (!SUPPORTED_PLATFORMS.includes(platform)) return false;
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) return false;
  let content = readTextFile(configFile);
  const existingRe = new RegExp(
    `^([ \\t]+${platform}:\\s*\\n[ \\t]+enabled:\\s*)(?:true|false)`,
    'm',
  );
  if (existingRe.test(content)) {
    content = content.replace(existingRe, `$1${enabled}`);
  } else {
    const block = `  ${platform}:\n    enabled: ${enabled}\n`;
    const platformsRe = /^(\s*platforms:\s*\n)/m;
    if (platformsRe.test(content)) {
      content = content.replace(platformsRe, `$1${block}`);
    } else {
      content = `${content.trimEnd()}\nplatforms:\n${block}`;
    }
  }
  writeTextFile(configFile, content);
  return true;
}
