import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import {
  dockerContainerLogs,
  dockerContainerPause,
  dockerContainerRemove,
  dockerContainerRename,
  dockerContainerRestart,
  dockerContainerStart,
  dockerContainerStats,
  dockerContainerStop,
  dockerContainerUnpause,
  dockerImageRemove,
  dockerPrune,
  inspectDockerContainer,
  listDockerContainers,
  listDockerImages,
  probeDockerAvailable,
} from '../admin/docker.js';

async function guardAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    return void reply.code(401).send({ message: '请先登录' });
  }
}

function dockerErrorMessage(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  if (/ENOENT|spawn docker/i.test(msg)) {
    return '网关容器内未安装 docker CLI，或无法执行 docker 命令。';
  }
  if (/permission denied|connect.*docker\.sock/i.test(msg)) {
    return '无法访问 Docker：请确认已挂载 /var/run/docker.sock 且容器有权限。';
  }
  return msg;
}

export const adminDockerRoutes: FastifyPluginAsync = async (app) => {
  app.get('/status', { preHandler: guardAdmin }, async () => {
    const available = await probeDockerAvailable();
    return { dockerAvailable: available };
  });

  app.get<{ Querystring: { search?: string; state?: string; project?: string } }>(
    '/containers',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        const containers = await listDockerContainers({
          search: req.query.search,
          state: req.query.state,
          project: req.query.project,
        });
        return { containers };
      } catch (err) {
        return reply.code(503).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.get('/images', { preHandler: guardAdmin }, async (_req, reply) => {
    try {
      const images = await listDockerImages();
      return { images };
    } catch (err) {
      return reply.code(503).send({ message: dockerErrorMessage(err) });
    }
  });

  app.post<{ Body: { targets?: string[] } }>('/prune', { preHandler: guardAdmin }, async (req, reply) => {
    try {
      const raw = req.body?.targets ?? [];
      const targets = raw.filter((t): t is 'containers' | 'images' => t === 'containers' || t === 'images');
      if (targets.length === 0) {
        return reply.code(400).send({ message: '请指定 targets: containers 和/或 images' });
      }
      const result = await dockerPrune(targets);
      return { ok: true, result };
    } catch (err) {
      return reply.code(400).send({ message: dockerErrorMessage(err) });
    }
  });

  app.get<{ Params: { id: string } }>('/containers/:id', { preHandler: guardAdmin }, async (req, reply) => {
    try {
      const detail = await inspectDockerContainer(req.params.id);
      return { detail };
    } catch (err) {
      return reply.code(400).send({ message: dockerErrorMessage(err) });
    }
  });

  app.get<{ Params: { id: string } }>('/containers/:id/stats', { preHandler: guardAdmin }, async (req, reply) => {
    try {
      const stats = await dockerContainerStats(req.params.id);
      return { stats };
    } catch (err) {
      return reply.code(400).send({ message: dockerErrorMessage(err) });
    }
  });

  app.get<{ Params: { id: string }; Querystring: { tail?: string } }>(
    '/containers/:id/logs',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        const tail = req.query.tail ? Number(req.query.tail) : 200;
        const logs = await dockerContainerLogs(req.params.id, tail);
        return { logs };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string } }>(
    '/containers/:id/start',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        await dockerContainerStart(req.params.id);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string } }>(
    '/containers/:id/stop',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        await dockerContainerStop(req.params.id);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string } }>(
    '/containers/:id/restart',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        await dockerContainerRestart(req.params.id);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string } }>(
    '/containers/:id/pause',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        await dockerContainerPause(req.params.id);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string } }>(
    '/containers/:id/unpause',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        await dockerContainerUnpause(req.params.id);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.post<{ Params: { id: string }; Body: { name?: string } }>(
    '/containers/:id/rename',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        const name = req.body?.name?.trim();
        if (!name) return reply.code(400).send({ message: '缺少 name' });
        await dockerContainerRename(req.params.id, name);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.delete<{ Params: { id: string }; Querystring: { force?: string } }>(
    '/containers/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        const force = req.query.force === 'true' || req.query.force === '1';
        await dockerContainerRemove(req.params.id, force);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );

  app.delete<{ Params: { id: string }; Querystring: { force?: string } }>(
    '/images/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        const force = req.query.force === 'true' || req.query.force === '1';
        await dockerImageRemove(req.params.id, force);
        return { ok: true };
      } catch (err) {
        return reply.code(400).send({ message: dockerErrorMessage(err) });
      }
    },
  );
};
