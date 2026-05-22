import { z } from 'zod';

/** static：仅 public/ 静态页；dynamic：启动 server/ 子进程并反代 /api */
export const projectTypeSchema = z.enum(['static', 'dynamic']);

export const projectManifestSchema = z.object({
  id: z.string().regex(/^[a-z0-9][a-z0-9_-]{0,63}$/),
  title: z.string().min(1).max(128),
  type: projectTypeSchema,
  version: z.string().default('1.0.0'),
  description: z.string().optional(),
  frontend: z
    .object({
      entry: z.string().default('public/index.html'),
    })
    .default({ entry: 'public/index.html' }),
  backend: z
    .object({
      command: z.string().default('node server/index.mjs'),
      cwd: z.string().default('server'),
      healthPath: z.string().default('/health'),
      port: z.number().int().min(1).max(65535).optional(),
    })
    .optional(),
  env: z.record(z.string()).optional(),
  createdAt: z.string().optional(),
  updatedAt: z.string().optional(),
});

export type ProjectManifest = z.infer<typeof projectManifestSchema>;
export type ProjectType = z.infer<typeof projectTypeSchema>;

export type ProjectRuntimeStatus = 'running' | 'stopped' | 'error' | 'starting';

export type ProjectSummary = {
  id: string;
  title: string;
  type: ProjectType;
  version: string;
  description?: string;
  status: ProjectRuntimeStatus;
  port?: number;
  pid?: number;
  error?: string;
  url: string;
  updatedAt?: string;
  lock?: {
    locked: boolean;
    reason: string;
    since: string;
    by: string;
  };
};
