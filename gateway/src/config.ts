import path from 'node:path';
import { config as loadEnv } from 'dotenv';
import { z } from 'zod';

import { resolveHermesApiOriginEnv } from './hermes-origin-env.js';

const envSchema = z.object({
  NODE_ENV: z.string().optional().default('development'),
  PORT: z.coerce.number().min(1).max(65535).default(3000),
  HOST: z.string().default('0.0.0.0'),
  JWT_SECRET: z.string().min(8, 'JWT_SECRET must be at least 8 characters'),
  /** Hermes Agent OpenAI-compatible API Server（默认 :8642） */
  HERMES_API_ORIGIN: z.string().url(),
  /** Hermes Dashboard REST（默认 :9119，可选） */
  HERMES_DASHBOARD_ORIGIN: z.string().url().optional(),
  /** 调用 API Server 的 Bearer（仅服务端，不下发 App） */
  HERMES_API_SERVER_KEY: z.string().min(1),
  /** Dashboard REST Authorization Bearer（可选） */
  HERMES_DASHBOARD_TOKEN: z.string().optional(),
  GATEWAY_VERSION: z.string().default('0.1.0'),

  HERMES_BACKUP_SOURCE: z.string().min(1),
  HERMES_BACKUP_DIR: z.string().min(1),
  HERMES_BACKUP_MAX: z.coerce.number().int().min(1).max(365).default(7),
  HERMES_DAILY_BACKUP_HOUR: z.coerce.number().int().min(0).max(23).default(2),
  HERMES_RESTART_SHELL: z.string().optional(),
  HERMES_MAINTENANCE_SHELL: z.string().optional(),
});

export type AppConfig = z.infer<typeof envSchema>;

let cached: AppConfig | null = null;

export function getDotenvPath(): string {
  const raw = process.env.GATEWAY_ENV_FILE?.trim();
  return raw ? path.resolve(raw) : path.join(process.cwd(), '.env');
}

function normalizeEnvAliases(): void {
  if (!process.env.HERMES_API_ORIGIN?.trim() && process.env.HERMES_ORIGIN?.trim()) {
    process.env.HERMES_API_ORIGIN = process.env.HERMES_ORIGIN.trim();
  }
}

function parseEnvOrThrow(): AppConfig {
  normalizeEnvAliases();
  resolveHermesApiOriginEnv();
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    const msg = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid environment: ${msg}`);
  }
  return parsed.data;
}

export function loadConfig(): AppConfig {
  if (cached) return cached;
  loadEnv({ path: getDotenvPath(), override: false });
  loadEnv({ path: getDotenvPath(), override: false });
  cached = parseEnvOrThrow();
  return cached;
}

export function reloadConfig(): AppConfig {
  cached = null;
  loadEnv({ path: getDotenvPath(), override: true });
  loadEnv({ path: getDotenvPath(), override: true });
  cached = parseEnvOrThrow();
  return cached;
}

/** App 登录校验（GATEWAY_AUTH_*，不在 zod 必填里以免旧 .env 启动失败） */
export function getGatewayAuthConfig(): {
  user: string | null;
  password: string | null;
} {
  const user = process.env.GATEWAY_AUTH_USER?.trim() || null;
  const password = process.env.GATEWAY_AUTH_PASSWORD?.trim() || null;
  return { user, password };
}

export function dashboardSessionsEnabled(cfg: AppConfig): boolean {
  return Boolean(cfg.HERMES_DASHBOARD_ORIGIN?.trim() && cfg.HERMES_DASHBOARD_TOKEN?.trim());
}
