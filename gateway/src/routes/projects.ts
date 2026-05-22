import { createReadStream, readFileSync, statSync } from 'node:fs';

import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import {
  initProjectLocks,
  isProjectLocked,
  withProjectLifecycleLock,
} from '../admin/projects-lock.js';
import {
  deleteProject,
  getProject,
  listProjects,
  proxyProjectApi,
  reconcileProjectRegistryOnBoot,
  resolvePublicFile,
  restartProject,
  startProject,
  stopProject,
  writePublicFile,
} from '../admin/projects-manager.js';
import { injectProjectHtml } from '../admin/project-html-inject.js';

async function guardJwt(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    reply.code(401).send({ message: '请先登录' });
  }
}

function slugParam(params: { slug?: string }): string {
  const slug = params.slug?.trim();
  if (!slug) throw new Error('缺少 slug');
  return slug;
}

export const projectsRoutes: FastifyPluginAsync = async (app) => {
  initProjectLocks();
  reconcileProjectRegistryOnBoot();

  app.get('/v1/projects', { preHandler: guardJwt }, async () => {
    return { projects: listProjects() };
  });

  app.get<{ Params: { slug: string } }>('/v1/projects/:slug/meta', { preHandler: guardJwt }, async (req, reply) => {
    try {
      return { project: getProject(slugParam(req.params)) };
    } catch (err) {
      return reply.code(404).send({ message: err instanceof Error ? err.message : String(err) });
    }
  });

  app.post<{ Params: { slug: string } }>(
    '/v1/projects/:slug/start',
    { preHandler: guardJwt },
    async (req, reply) => {
      try {
        const slug = slugParam(req.params);
        const project = await withProjectLifecycleLock(slug, '正在启动', () => startProject(slug));
        return { ok: true, project };
      } catch (err) {
        return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  app.post<{ Params: { slug: string } }>(
    '/v1/projects/:slug/stop',
    { preHandler: guardJwt },
    async (req, reply) => {
      try {
        const slug = slugParam(req.params);
        const project = await withProjectLifecycleLock(slug, '正在停止', () => stopProject(slug));
        return { ok: true, project };
      } catch (err) {
        return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  app.post<{ Params: { slug: string } }>(
    '/v1/projects/:slug/restart',
    { preHandler: guardJwt },
    async (req, reply) => {
      try {
        const slug = slugParam(req.params);
        const project = await withProjectLifecycleLock(slug, '正在重启', () => restartProject(slug));
        return { ok: true, project };
      } catch (err) {
        return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  app.put<{
    Params: { slug: string };
    Body: { path?: string; contentBase64: string };
  }>(
    '/v1/projects/:slug/public',
    { preHandler: guardJwt },
    async (req, reply) => {
      try {
        const slug = slugParam(req.params);
        if (isProjectLocked(slug)) {
          return reply.code(423).send({ message: '项目正在更新中，请稍候再同步文件' });
        }
        const rel = (req.body?.path ?? 'index.html').trim() || 'index.html';
        const b64 = req.body?.contentBase64?.trim();
        if (!b64) {
          return reply.code(400).send({ message: '缺少 contentBase64' });
        }
        const content = Buffer.from(b64, 'base64').toString('utf8');
        writePublicFile(slug, rel, content);
        return { ok: true, path: rel, bytes: content.length };
      } catch (err) {
        return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  app.delete<{ Params: { slug: string }; Querystring: { confirm?: string } }>(
    '/v1/projects/:slug',
    { preHandler: guardJwt },
    async (req, reply) => {
      if (req.query.confirm !== '1') {
        return reply.code(400).send({ message: '删除需 confirm=1' });
      }
      try {
        const slug = slugParam(req.params);
        await withProjectLifecycleLock(slug, '正在删除', async () => {
          await deleteProject(slug);
        });
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  /** API 反代：/v1/projects/:slug/api/* → 127.0.0.1:port */
  app.all<{ Params: { slug: string; '*': string } }>(
    '/v1/projects/:slug/api/*',
    { preHandler: guardJwt },
    async (req, reply) => {
      const slug = slugParam(req.params);
      if (isProjectLocked(slug)) {
        return reply.code(423).send({ message: '项目正在更新中，API 暂不可用' });
      }
      const wild = (req.params as { '*': string })['*'] ?? '';
      const apiPath = `/api/${wild}`.replace(/\/+/g, '/');
      try {
        const headers: Record<string, string> = {};
        for (const [k, v] of Object.entries(req.headers)) {
          if (v == null || k === 'host' || k === 'authorization') continue;
          headers[k] = Array.isArray(v) ? v.join(',') : String(v);
        }
        let body: string | undefined;
        if (req.method !== 'GET' && req.method !== 'HEAD' && req.body != null) {
          body = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
          if (!headers['content-type']) headers['content-type'] = 'application/json';
        }
        const upstream = await proxyProjectApi(slug, apiPath + (req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''), {
          method: req.method,
          headers,
          body,
        });
        reply.code(upstream.status);
        upstream.headers.forEach((val, key) => {
          if (key.toLowerCase() === 'transfer-encoding') return;
          reply.header(key, val);
        });
        const buf = Buffer.from(await upstream.arrayBuffer());
        return reply.send(buf);
      } catch (err) {
        return reply.code(502).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  /** 静态前端：/v1/projects/:slug/* */
  app.get<{ Params: { slug: string; '*': string } }>(
    '/v1/projects/:slug/*',
    { preHandler: guardJwt },
    async (req, reply) => {
      const slug = slugParam(req.params);
      const wild = (req.params as { '*': string })['*'] ?? '';
      try {
        const { filePath, mime } = resolvePublicFile(slug, wild || 'index.html');
        const stat = statSync(filePath);
        reply.header('Content-Type', mime);
        reply.header('Cache-Control', 'no-cache');
        if (mime.includes('html')) {
          let html = readFileSync(filePath, 'utf8');
          html = injectProjectHtml(html, slug);
          return reply.send(html);
        }
        return reply.send(createReadStream(filePath));
      } catch (err) {
        return reply.code(404).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );

  app.get<{ Params: { slug: string } }>(
    '/v1/projects/:slug/',
    { preHandler: guardJwt },
    async (req, reply) => {
      const slug = slugParam(req.params);
      try {
        const { filePath, mime } = resolvePublicFile(slug, 'index.html');
        let html = readFileSync(filePath, 'utf8');
        html = injectProjectHtml(html, slug);
        reply.header('Content-Type', mime);
        return reply.send(html);
      } catch (err) {
        return reply.code(404).send({ message: err instanceof Error ? err.message : String(err) });
      }
    },
  );
};
