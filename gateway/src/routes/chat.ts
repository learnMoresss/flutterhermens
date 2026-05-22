import { Readable } from 'node:stream';
import { ReadableStream } from 'node:stream/web';

import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';

import { normalizeChatImagesForHermes } from '../admin/chat-attachments.js';
import {
  injectCreateAppSystemPrompt,
  injectTargetProjectContext,
} from '../admin/create-app-prompt.js';
import { injectMobileBffSystemPrompt } from '../admin/mobile-bff-prompt.js';
import { rewriteJsonResponse } from '../admin/media-url-rewrite.js';
import {
  attachUnlockOnStreamEnd,
  getProjectLock,
  lockProject,
  unlockProject,
} from '../admin/projects-lock.js';
import { SseMediaRewriteTransform } from '../admin/sse-media-rewrite.js';
import { loadConfig } from '../config.js';
import { proxyChatCompletions } from '../hermes/api-server.js';

const messageSchema = z.object({
  role: z.enum(['system', 'user', 'assistant']),
  content: z.unknown(),
});

const chatBodySchema = z.object({
  messages: z.array(messageSchema).min(1),
  model: z.string().optional(),
  session_id: z.string().optional(),
  stream: z.boolean().optional().default(true),
  create_app_mode: z.boolean().optional(),
  /** App 当前正在查看的项目；create_app_mode 时锁定直至对话结束 */
  target_project_slug: z.string().optional(),
});

const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

export const chatRoutes: FastifyPluginAsync = async (app) => {
  app.post<{ Body: unknown }>('/v1/chat/completions', async (req, reply) => {
    const cfg = loadConfig();
    try {
      await req.jwtVerify();
    } catch {
      return reply.code(401).send({ message: '未授权：请先登录' });
    }

    const parsedBody = chatBodySchema.safeParse(req.body);
    if (!parsedBody.success) {
      return reply.code(400).send({ message: '无效的请求体' });
    }

    const { create_app_mode, target_project_slug, ...chatFields } = parsedBody.data;
    const targetSlug = target_project_slug?.trim();
    let lockedSlug: string | undefined;

    if (targetSlug) {
      if (!SLUG_RE.test(targetSlug)) {
        return reply.code(400).send({ message: '无效的 target_project_slug' });
      }
      if (create_app_mode) {
        const existing = getProjectLock(targetSlug);
        if (existing?.locked && existing.by !== 'chat') {
          return reply.code(409).send({ message: `项目「${targetSlug}」正在更新中，请稍候` });
        }
        try {
          lockProject(targetSlug, 'Hermes 正在更新此应用', 'chat');
          lockedSlug = targetSlug;
        } catch (err) {
          return reply.code(400).send({ message: err instanceof Error ? err.message : String(err) });
        }
      }
    }

    const releaseLock = () => {
      if (lockedSlug) {
        unlockProject(lockedSlug);
        lockedSlug = undefined;
      }
    };

    try {
      let messages = injectMobileBffSystemPrompt(chatFields.messages);
      if (create_app_mode) {
        messages = injectCreateAppSystemPrompt(messages);
        if (targetSlug) {
          messages = injectTargetProjectContext(messages, targetSlug);
        }
      }
      const upstreamBody = {
        ...chatFields,
        messages: normalizeChatImagesForHermes(messages),
      };
      const upstream = await proxyChatCompletions(cfg, upstreamBody, req.signal);
      const ct = upstream.headers.get('content-type') ?? '';

      if (!upstream.ok) {
        releaseLock();
        const txt = await upstream.text().catch(() => '');
        let message = txt.slice(0, 500);
        try {
          const j = JSON.parse(txt) as { message?: string; error?: { message?: string } };
          message = j.message ?? j.error?.message ?? message;
        } catch {
          /* keep raw */
        }
        return reply.code(upstream.status).send({
          message: message || `Hermes API 错误 ${upstream.status}`,
        });
      }

      const sessionId = upstream.headers.get('x-hermes-session-id');
      if (sessionId) {
        reply.header('x-hermes-session-id', sessionId);
      }

      if (parsedBody.data.stream && ct.includes('text/event-stream')) {
        reply.header('Content-Type', 'text/event-stream; charset=utf-8');
        reply.header('Cache-Control', 'no-cache');
        reply.header('Connection', 'keep-alive');
        if (!upstream.body) {
          releaseLock();
          return reply.send('');
        }
        const nodeStream = Readable.fromWeb(upstream.body as ReadableStream<Uint8Array>);
        const out = nodeStream.pipe(new SseMediaRewriteTransform());
        if (lockedSlug) {
          attachUnlockOnStreamEnd(out, lockedSlug);
          lockedSlug = undefined;
        }
        return reply.send(out);
      }

      const json = await upstream.json();
      releaseLock();
      return reply.send(rewriteJsonResponse(json));
    } catch (err) {
      releaseLock();
      throw err;
    }
  });
};
