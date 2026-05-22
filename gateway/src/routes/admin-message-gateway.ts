import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import {
  getMessageGatewayStatus,
  startMessageGateway,
  stopMessageGateway,
} from '../admin/agent-message-gateway.js';

async function guardAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    return void reply.code(401).send({ message: '请先登录' });
  }
}

export const adminMessageGatewayRoutes: FastifyPluginAsync = async (app) => {
  app.get('/status', { preHandler: guardAdmin }, async () => getMessageGatewayStatus());

  app.post('/start', { preHandler: guardAdmin }, async (_req, reply) => {
    const r = await startMessageGateway();
    if (!r.ok) return reply.code(502).send({ message: r.error ?? '启动失败' });
    return { ok: true, ...(await getMessageGatewayStatus()) };
  });

  app.post('/stop', { preHandler: guardAdmin }, async (_req, reply) => {
    const r = await stopMessageGateway();
    if (!r.ok) return reply.code(502).send({ message: r.error ?? '停止失败' });
    return { ok: true, ...(await getMessageGatewayStatus()) };
  });
};
