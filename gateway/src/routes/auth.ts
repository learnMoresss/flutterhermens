import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

export const authRoutes: FastifyPluginAsync = async (app) => {
  app.post('/v1/auth/refresh', async (req, reply) => {
    try {
      await req.jwtVerify();
    } catch {
      return reply.code(401).send({ message: '登录已过期，请重新登录' });
    }

    const payload = req.user as { sub?: string };
    const username = payload.sub ?? 'user';
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const token = app.jwt.sign({ sub: username }, { expiresIn: '24h' });
    return { token, expiresAt, username };
  });
};
