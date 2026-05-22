import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import { loadConfig } from '../config.js';

async function guardJwt(req: FastifyRequest, reply: FastifyReply): Promise<boolean> {
  try {
    await req.jwtVerify();
    return true;
  } catch {
    reply.code(401).send({ message: '请先登录' });
    return false;
  }
}

/** Hermes 移动端当前使用 HTTP SSE 流式；此端点说明 WS 透传配置状态。 */
export const wsInfoRoutes: FastifyPluginAsync = async (app) => {
  app.get('/v1/ws/info', async (req, reply) => {
    if (!(await guardJwt(req, reply))) return;
    const cfg = loadConfig();
    const wsOrigin = process.env.HERMES_WS_ORIGIN?.trim() ?? '';
    return {
      available: Boolean(wsOrigin),
      wsOrigin: wsOrigin || null,
      httpStreaming: true,
      hermesApiOrigin: cfg.HERMES_API_ORIGIN,
      note: 'App 当前通过 POST /v1/chat/completions SSE 流式聊天；配置 HERMES_WS_ORIGIN 后可扩展 WS 透传。',
    };
  });
};
