import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';

import { loadConfig } from '../config.js';
import { fetchHermesApi } from '../hermes/api-server.js';

async function guardAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    return void reply.code(401).send({ message: '请先登录' });
  }
}

async function proxyJobsJson(
  reply: FastifyReply,
  pathname: string,
  init?: RequestInit,
): Promise<void> {
  const cfg = loadConfig();
  const path = pathname.startsWith('/') ? pathname : `/${pathname}`;
  const res = await fetchHermesApi(cfg, path, init);
  const txt = await res.text();
  const ct = res.headers.get('content-type') ?? 'application/json';
  reply.code(res.status).header('Content-Type', ct);
  try {
    reply.send(JSON.parse(txt));
  } catch {
    reply.send(txt);
  }
}

const createJobSchema = z.object({
  name: z.string().optional().default(''),
  schedule: z.string().min(1),
  prompt: z.string().optional().default(''),
  deliver: z.string().optional().default('local'),
});

export const adminJobsRoutes: FastifyPluginAsync = async (app) => {
  app.get<{ Querystring: { include_disabled?: string } }>(
    '/',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const includeDisabled = req.query.include_disabled !== 'false';
      const qs = includeDisabled ? '?include_disabled=true' : '';
      await proxyJobsJson(reply, `/api/jobs${qs}`);
    },
  );

  app.post<{ Body: unknown }>('/', { preHandler: guardAdmin }, async (req, reply) => {
    const parsed = createJobSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ message: '无效的请求体' });
    }
    await proxyJobsJson(reply, '/api/jobs', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(parsed.data),
    });
  });

  app.delete<{ Params: { id: string } }>(
    '/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const id = encodeURIComponent(req.params.id);
      await proxyJobsJson(reply, `/api/jobs/${id}`, { method: 'DELETE' });
    },
  );

  app.post<{ Params: { id: string; action: string } }>(
    '/:id/:action',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const action = req.params.action;
      if (!['pause', 'resume', 'run'].includes(action)) {
        return reply.code(400).send({ message: '不支持的操作' });
      }
      const id = encodeURIComponent(req.params.id);
      await proxyJobsJson(reply, `/api/jobs/${id}/${action}`, { method: 'POST' });
    },
  );
};
