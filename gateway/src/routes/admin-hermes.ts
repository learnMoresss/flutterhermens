import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';

import { z } from 'zod';

import { getDotenvPath, loadConfig, reloadConfig } from '../config.js';

import {

  createHermesArchive,

  getEffectiveMaxBackups,

  getScheduleState,

  listBackups,

  restoreHermesArchive,

  setMaxBackups,

} from '../admin/hermes-backup.js';

import { listLogFiles, listMcpServers, readHermesLogs, runHermesDoctor } from '../admin/agent-ops.js';

import { runShellLine } from '../admin/run-shell.js';



async function guardAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    return void reply.code(401).send({ message: '请先登录' });
  }
}



export const adminHermesRoutes: FastifyPluginAsync = async (app) => {

  app.get(

    '/status',

    { preHandler: guardAdmin },

    async () => {

      const cfg = loadConfig();

      const backups = await listBackups(cfg);

      const max = await getEffectiveMaxBackups(cfg);

      const schedule = await getScheduleState(cfg);

      return {

        hermesApiOrigin: cfg.HERMES_API_ORIGIN,

        backupSource: cfg.HERMES_BACKUP_SOURCE,

        backupDir: cfg.HERMES_BACKUP_DIR,

        dailyBackupHour: cfg.HERMES_DAILY_BACKUP_HOUR,

        maxBackups: max,

        backupCount: backups.length,

        lastDailyBackupAt: schedule.lastDailyBackupAt,

        restartConfigured: Boolean(cfg.HERMES_RESTART_SHELL?.trim()),

        maintenanceConfigured: Boolean(cfg.HERMES_MAINTENANCE_SHELL?.trim()),

        dotenvPath: getDotenvPath(),

      };

    },

  );



  app.get('/backups', { preHandler: guardAdmin }, async () => {

    const cfg = loadConfig();

    return {

      backups: await listBackups(cfg),

    };

  });



  app.post('/backup', { preHandler: guardAdmin }, async () => {

    const cfg = loadConfig();

    const name = await createHermesArchive(cfg);

    return { ok: true, filename: name };

  });



  app.post<{ Body: unknown }>('/restore', { preHandler: guardAdmin }, async (req, reply) => {

    const cfg = loadConfig();

    const body = z.object({ filename: z.string() }).safeParse(req.body);

    if (!body.success) {

      return reply.code(400).send({ message: '无效请求体' });

    }

    await restoreHermesArchive(cfg, body.data.filename);

    return { ok: true };

  });



  app.post('/restart', { preHandler: guardAdmin }, async (req, reply) => {

    const cfg = loadConfig();

    const line = cfg.HERMES_RESTART_SHELL?.trim();

    if (!line) {

      return reply.code(400).send({ message: '未配置 HERMES_RESTART_SHELL' });

    }

    const r = await runShellLine(line, 300_000);

    if (r.code !== 0) {

      return reply.code(502).send({

        message: '重启命令非零退出',

        stderr: r.stderr.slice(0, 2000),

        stdout: r.stdout.slice(0, 2000),

      });

    }

    return { ok: true, stdout: r.stdout.slice(0, 4000) };

  });



  app.post<{ Body: unknown }>('/run', { preHandler: guardAdmin }, async (req, reply) => {

    const cfg = loadConfig();

    const body = z.object({ preset: z.enum(['maintenance']) }).safeParse(req.body);

    if (!body.success) {

      return reply.code(400).send({ message: '无效请求体：preset 仅支持 maintenance' });

    }

    const line = cfg.HERMES_MAINTENANCE_SHELL?.trim();

    if (!line) {

      return reply.code(400).send({ message: '未配置 HERMES_MAINTENANCE_SHELL' });

    }

    const r = await runShellLine(line, 300_000);

    if (r.code !== 0) {

      return reply.code(502).send({

        message: '命令非零退出',

        stderr: r.stderr.slice(0, 2000),

        stdout: r.stdout.slice(0, 2000),

      });

    }

    return { ok: true, stdout: r.stdout.slice(0, 4000) };

  });



  app.get('/retention', { preHandler: guardAdmin }, async () => {

    const cfg = loadConfig();

    return {

      maxBackups: await getEffectiveMaxBackups(cfg),

    };

  });



  app.put<{ Body: unknown }>('/retention', { preHandler: guardAdmin }, async (req, reply) => {

    const cfg = loadConfig();

    const body = z.object({ maxBackups: z.number().int().min(1).max(365) }).safeParse(req.body);

    if (!body.success) {

      return reply.code(400).send({ message: '无效请求体' });

    }

    await setMaxBackups(cfg, body.data.maxBackups);

    return { ok: true, maxBackups: body.data.maxBackups };

  });



  /** 重新读取磁盘上的 `.env` 并刷新内存中的配置（Hermes 路径、管理密钥等）。 */

  app.post('/config/reload', { preHandler: guardAdmin }, async () => {

    const cfg = reloadConfig();

    return { ok: true, dotenvPath: getDotenvPath(), hermesApiOrigin: cfg.HERMES_API_ORIGIN };

  });

  app.get<{ Querystring: { file?: string; tail?: string } }>(
    '/logs',
    { preHandler: guardAdmin },
    async (req) => {
      const file = req.query.file ?? 'gateway.log';
      const tail = parseInt(req.query.tail ?? '500', 10);
      const result = readHermesLogs(file, Number.isNaN(tail) ? 500 : tail);
      return {
        ...result,
        files: listLogFiles(),
      };
    },
  );

  app.post('/doctor', { preHandler: guardAdmin }, async () => runHermesDoctor());

  app.get('/mcp', { preHandler: guardAdmin }, async () => ({
    servers: listMcpServers(),
  }));

  app.post<{ Body: unknown }>('/import', { preHandler: guardAdmin }, async (req, reply) => {
    const body = z.object({ archivePath: z.string().min(1) }).safeParse(req.body);
    if (!body.success) return reply.code(400).send({ message: '无效请求体：需要 archivePath' });
    const line = process.env.HERMES_IMPORT_SHELL?.trim();
    if (!line) {
      return reply.code(400).send({ message: '未配置 HERMES_IMPORT_SHELL' });
    }
    const cmd = line.replace('{{path}}', body.data.archivePath);
    const r = await runShellLine(cmd, 600_000);
    if (r.code !== 0) {
      return reply.code(502).send({
        message: '导入失败',
        stderr: r.stderr.slice(0, 2000),
        stdout: r.stdout.slice(0, 2000),
      });
    }
    return { ok: true, stdout: r.stdout.slice(0, 4000) };
  });

};


