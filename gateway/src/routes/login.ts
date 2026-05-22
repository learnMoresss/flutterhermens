import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';

import { getGatewayAuthConfig, loadConfig } from '../config.js';

const loginBody = z.object({
  username: z.string(),
  password: z.string(),
});

export const loginRoutes: FastifyPluginAsync = async (app) => {
  app.post<{ Body: unknown }>('/v1/login', async (req, reply) => {
    loadConfig();
    const { user: authUser, password: authPassword } = getGatewayAuthConfig();
    if (!authPassword) {
      return reply.code(501).send({
        message: '未配置 GATEWAY_AUTH_PASSWORD，无法登录。',
      });
    }

    const parsed = loginBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ message: '无效的请求体' });
    }

    const { username, password } = parsed.data;
    if (authUser && username !== authUser) {
      return reply.code(401).send({ message: '用户名或密码错误' });
    }
    if (password !== authPassword) {
      return reply.code(401).send({ message: '用户名或密码错误' });
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const token = app.jwt.sign({ sub: username }, { expiresIn: '24h' });
    return { token, expiresAt, username };
  });
};
