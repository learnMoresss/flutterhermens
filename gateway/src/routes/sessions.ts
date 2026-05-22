import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import { dashboardSessionsEnabled, loadConfig } from '../config.js';
import { fetchHermesDashboard } from '../hermes/dashboard.js';

async function requireAppJwt(req: FastifyRequest, reply: FastifyReply): Promise<boolean> {
  try {
    await req.jwtVerify();
    return true;
  } catch {
    reply.code(401).send({ message: '未授权：请先登录' });
    return false;
  }
}

async function proxyDashboardJson(
  req: FastifyRequest,
  reply: FastifyReply,
  pathname: string,
  init?: RequestInit,
): Promise<void> {
  const cfg = loadConfig();
  if (!dashboardSessionsEnabled(cfg)) {
    reply.code(503).send({
      message: '未配置 HERMES_DASHBOARD_ORIGIN / HERMES_DASHBOARD_TOKEN，会话 API 不可用。',
    });
    return;
  }

  const res = await fetchHermesDashboard(cfg, pathname, init);
  const txt = await res.text();
  const ct = res.headers.get('content-type') ?? 'application/json';
  reply.code(res.status).header('Content-Type', ct);
  try {
    reply.send(JSON.parse(txt));
  } catch {
    reply.send(txt);
  }
}

export const sessionsRoutes: FastifyPluginAsync = async (app) => {
  app.get('/v1/sessions', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    await proxyDashboardJson(req, reply, '/api/sessions');
  });

  app.get<{ Params: { id: string } }>('/v1/sessions/:id', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    const id = encodeURIComponent(req.params.id);
    await proxyDashboardJson(req, reply, `/api/sessions/${id}`);
  });

  app.get<{ Params: { id: string } }>('/v1/sessions/:id/messages', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    const id = encodeURIComponent(req.params.id);
    await proxyDashboardJson(req, reply, `/api/sessions/${id}/messages`);
  });

  app.get<{ Querystring: { q?: string } }>('/v1/sessions/search', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    const q = (req.query.q ?? '').trim();
    const qs = q ? `?q=${encodeURIComponent(q)}` : '';
    await proxyDashboardJson(req, reply, `/api/sessions/search${qs}`);
  });

  app.delete<{ Params: { id: string } }>('/v1/sessions/:id', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    const id = encodeURIComponent(req.params.id);
    await proxyDashboardJson(req, reply, `/api/sessions/${id}`, { method: 'DELETE' });
  });

  app.patch<{ Params: { id: string }; Body: unknown }>('/v1/sessions/:id', async (req, reply) => {
    if (!(await requireAppJwt(req, reply))) return;
    const id = encodeURIComponent(req.params.id);
    await proxyDashboardJson(req, reply, `/api/sessions/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body ?? {}),
    });
  });
};
