import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';

import {
  buildCreateAppDelegationBrief,
  CREATE_APP_DELEGATION_MARKER,
  CREATE_APP_FOLDER_ANTI_PATTERNS,
} from '../admin/create-app-delegation.js';
import {
  buildHermesAppSnippetsScript,
  HERMES_APP_ANTI_PATTERNS,
} from '../admin/hermes-app-snippets.js';
import { getProjectsRoot, getPublicBaseUrlForProjects } from '../admin/projects-manager.js';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

const briefQuerySchema = z.object({
  slug: z
    .string()
    .regex(/^[a-z0-9][a-z0-9_-]{0,63}$/)
    .optional(),
});

function resolveHostJsPath(): string | null {
  const candidates = [
    join(MODULE_DIR, '../../public/hermes-app-host.js'),
    join(process.cwd(), 'public', 'hermes-app-host.js'),
    join(process.cwd(), 'dist', 'public', 'hermes-app-host.js'),
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return null;
}

let cachedJs: string | null = null;

function loadHostJs(): string {
  if (cachedJs) return cachedJs;
  const path = resolveHostJsPath();
  if (!path) {
    cachedJs = '/* hermes-app-host.js missing */';
    return cachedJs;
  }
  cachedJs = readFileSync(path, 'utf8');
  return cachedJs;
}

export const hermesAppRoutes: FastifyPluginAsync = async (app) => {
  app.get('/v1/hermes-app/host.js', async (_req, reply) => {
    reply.header('Content-Type', 'application/javascript; charset=utf-8');
    reply.header('Cache-Control', 'public, max-age=3600');
    return reply.send(loadHostJs());
  });

  app.get('/v1/hermes-app/snippets.js', async (_req, reply) => {
    reply.header('Content-Type', 'application/javascript; charset=utf-8');
    reply.header('Cache-Control', 'public, max-age=3600');
    return reply.send(buildHermesAppSnippetsScript());
  });

  app.get<{ Querystring: unknown }>('/v1/hermes-app/create-app-brief', async (req, reply) => {
    try {
      await req.jwtVerify();
    } catch {
      return reply.code(401).send({ message: '未授权：请先登录' });
    }

    const parsed = briefQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      return reply.code(400).send({ message: '无效的 slug 参数' });
    }

    const projectsRoot = getProjectsRoot();
    const publicBase = getPublicBaseUrlForProjects();
    const slug = parsed.data.slug;
    const mode = slug ? 'modify' : 'create';

    return reply.send({
      marker: CREATE_APP_DELEGATION_MARKER,
      projectsRoot,
      publicBase,
      slug: slug ?? null,
      mode,
      folderAntiPatterns: CREATE_APP_FOLDER_ANTI_PATTERNS,
      hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
      briefMarkdown: buildCreateAppDelegationBrief({
        projectsRoot,
        publicBase,
        slug,
        mode,
        hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
      }),
    });
  });
};
