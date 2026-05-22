import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';

import {
  getConfigSummary,
  getPlatformEnabled,
  listEnvKeys,
  setEnvKey,
  setModelConfig,
  setPlatformEnabled,
} from '../admin/agent-env.js';
import {
  addMemoryEntry,
  discoverMemoryProviders,
  readMemory,
  removeMemoryEntry,
  updateMemoryEntry,
  writeMemoryContent,
  writeUserProfile,
} from '../admin/agent-memory.js';
import {
  addSavedModel,
  getHermesHome,
  listSavedModels,
  removeSavedModel,
  updateSavedModel,
} from '../admin/agent-models.js';
import {
  createProfileViaCli,
  deleteProfileViaCli,
  listProfiles,
  setActiveProfile,
} from '../admin/agent-profiles.js';
import {
  getSkillContentById,
  installSkillViaCli,
  listBundledSkills,
  listInstalledSkills,
  uninstallSkillViaCli,
} from '../admin/agent-skills.js';
import { readSoul, resetSoul, writeSoul } from '../admin/agent-soul.js';
import { listToolsets, setToolsetEnabled } from '../admin/agent-toolsets.js';

async function guardAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    return void reply.code(401).send({ message: '请先登录' });
  }
}

export const adminAgentRoutes: FastifyPluginAsync = async (app) => {
  app.get('/status', { preHandler: guardAdmin }, async () => ({
    hermesHome: getHermesHome(),
    config: getConfigSummary(),
    gatewayVersion: process.env.GATEWAY_VERSION ?? '0.1.0',
  }));

  app.get('/models', { preHandler: guardAdmin }, async () => ({
    models: listSavedModels(),
    hermesHome: getHermesHome(),
  }));

  app.post<{ Body: unknown }>('/models', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z
      .object({
        name: z.string().min(1),
        provider: z.string().min(1),
        model: z.string().min(1),
        baseUrl: z.string().optional().default(''),
      })
      .safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const entry = addSavedModel(body.data.name, body.data.provider, body.data.model, body.data.baseUrl);
    return { ok: true, model: entry, models: listSavedModels() };
  });

  app.put<{ Params: { id: string }; Body: unknown }>(
    '/models/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const body = z
        .object({
          name: z.string().optional(),
          provider: z.string().optional(),
          model: z.string().optional(),
          baseUrl: z.string().optional(),
        })
        .safeParse(req.body);
      if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
      const ok = updateSavedModel(req.params.id, body.data);
      if (!ok) return reply.code(404).send({ message: '模型不存在' });
      return { ok: true, models: listSavedModels() };
    },
  );

  app.delete<{ Params: { id: string } }>(
    '/models/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const ok = removeSavedModel(req.params.id);
      if (!ok) return reply.code(404).send({ message: '模型不存在' });
      return { ok: true, models: listSavedModels() };
    },
  );

  app.get('/toolsets', { preHandler: guardAdmin }, async () => ({
    toolsets: listToolsets(),
  }));

  app.put<{ Params: { key: string }; Body: unknown }>(
    '/toolsets/:key',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const body = z.object({ enabled: z.boolean() }).safeParse(req.body);
      if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
      const ok = setToolsetEnabled(req.params.key, body.data.enabled);
      if (!ok) return reply.code(404).send({ message: '无法更新工具集（config.yaml 不存在或键无效）' });
      return { ok: true, toolsets: listToolsets() };
    },
  );

  app.get('/soul', { preHandler: guardAdmin }, async () => ({
    content: readSoul(),
  }));

  app.put<{ Body: unknown }>('/soul', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ content: z.string() }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    writeSoul(body.data.content);
    return { ok: true };
  });

  app.post('/soul/reset', { preHandler: guardAdmin }, async () => ({
    ok: true,
    content: resetSoul(),
  }));

  app.get('/skills', { preHandler: guardAdmin }, async () => ({
    skills: listInstalledSkills(),
  }));

  app.get('/skills/bundled', { preHandler: guardAdmin }, async () => ({
    skills: listBundledSkills(),
  }));

  app.get<{ Params: { id: string } }>(
    '/skills/:id/content',
    { preHandler: guardAdmin },
    async (req) => ({
      content: getSkillContentById(decodeURIComponent(req.params.id)),
    }),
  );

  app.post<{ Params: { id: string } }>(
    '/skills/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const id = decodeURIComponent(req.params.id);
      const r = await installSkillViaCli(id);
      if (!r.ok) return reply.code(502).send({ message: r.error ?? '安装失败' });
      return { ok: true, skills: listInstalledSkills() };
    },
  );

  app.delete<{ Params: { id: string } }>(
    '/skills/:id',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const id = decodeURIComponent(req.params.id);
      const name = id.includes('/') ? id.split('/').pop()! : id;
      const r = await uninstallSkillViaCli(name);
      if (!r.ok) return reply.code(502).send({ message: r.error ?? '卸载失败' });
      return { ok: true, skills: listInstalledSkills() };
    },
  );

  app.get('/profiles', { preHandler: guardAdmin }, async () => ({
    profiles: listProfiles(),
    active: listProfiles().find((p) => p.isActive)?.name ?? 'default',
  }));

  app.post<{ Body: unknown }>('/profiles', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z
      .object({ name: z.string().min(1), clone: z.boolean().optional().default(false) })
      .safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = await createProfileViaCli(body.data.name, body.data.clone);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '创建失败' });
    return { ok: true, profiles: listProfiles() };
  });

  app.delete<{ Params: { name: string } }>(
    '/profiles/:name',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const r = await deleteProfileViaCli(req.params.name);
      if (!r.ok) return reply.code(400).send({ message: r.error ?? '删除失败' });
      return { ok: true, profiles: listProfiles() };
    },
  );

  app.post<{ Params: { name: string } }>(
    '/profiles/:name/activate',
    { preHandler: guardAdmin },
    async (req, reply) => {
      try {
        setActiveProfile(req.params.name);
        return { ok: true, profiles: listProfiles() };
      } catch (err) {
        return reply.code(400).send({ message: (err as Error).message });
      }
    },
  );

  app.get('/providers', { preHandler: guardAdmin }, async () => ({
    keys: listEnvKeys(),
    config: getConfigSummary(),
  }));

  app.put<{ Body: unknown }>('/providers/env', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ key: z.string(), value: z.string() }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = setEnvKey(body.data.key, body.data.value);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '写入失败' });
    return { ok: true, keys: listEnvKeys() };
  });

  app.put<{ Body: unknown }>('/providers/config', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z
      .object({
        provider: z.string().optional(),
        model: z.string().optional(),
        baseUrl: z.string().optional(),
      })
      .safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = setModelConfig(body.data);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '更新失败' });
    return { ok: true, config: getConfigSummary(), keys: listEnvKeys() };
  });

  app.get('/memory', { preHandler: guardAdmin }, async () => readMemory());

  app.put<{ Body: unknown }>('/memory', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ content: z.string() }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = writeMemoryContent(body.data.content);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '写入失败' });
    return { ok: true, ...readMemory() };
  });

  app.put<{ Body: unknown }>('/memory/user', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ content: z.string() }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = writeUserProfile(body.data.content);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '写入失败' });
    return { ok: true, ...readMemory() };
  });

  app.post<{ Body: unknown }>('/memory/entries', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ content: z.string().min(1) }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
    const r = addMemoryEntry(body.data.content);
    if (!r.ok) return reply.code(400).send({ message: r.error ?? '添加失败' });
    return { ok: true, ...readMemory() };
  });

  app.put<{ Params: { index: string }; Body: unknown }>(
    '/memory/entries/:index',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const index = parseInt(req.params.index, 10);
      const body = z.object({ content: z.string().min(1) }).safeParse(req.body);
      if (!body.success || Number.isNaN(index)) {
        return reply.code(400).send({ message: '无效的请求体' });
      }
      const r = updateMemoryEntry(index, body.data.content);
      if (!r.ok) return reply.code(400).send({ message: r.error ?? '更新失败' });
      return { ok: true, ...readMemory() };
    },
  );

  app.delete<{ Params: { index: string } }>(
    '/memory/entries/:index',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const index = parseInt(req.params.index, 10);
      if (Number.isNaN(index)) return reply.code(400).send({ message: '无效索引' });
      const ok = removeMemoryEntry(index);
      if (!ok) return reply.code(404).send({ message: '条目不存在' });
      return { ok: true, ...readMemory() };
    },
  );

  app.get('/memory/providers', { preHandler: guardAdmin }, async () => ({
    providers: discoverMemoryProviders(),
  }));

  app.get('/platforms', { preHandler: guardAdmin }, async () => ({
    platforms: getPlatformEnabled(),
  }));

  app.put<{ Params: { key: string }; Body: unknown }>(
    '/platforms/:key',
    { preHandler: guardAdmin },
    async (req, reply) => {
      const body = z.object({ enabled: z.boolean() }).safeParse(req.body);
      if (!body.success) return reply.code(400).send({ message: '无效的请求体' });
      const ok = setPlatformEnabled(req.params.key, body.data.enabled);
      if (!ok) return reply.code(404).send({ message: '无效的平台键' });
      return { ok: true, platforms: getPlatformEnabled() };
    },
  );
};
