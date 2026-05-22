import type { FastifyInstance } from 'fastify';
import { loadConfig } from '../config.js';
import { maybeRunScheduledDailyBackup } from './hermes-backup.js';

let started = false;

export function startHermesAdminScheduler(app: FastifyInstance): void {
  if (started) return;
  started = true;
  const tick = async () => {
    try {
      const cfg = loadConfig();
      const ran = await maybeRunScheduledDailyBackup(cfg);
      if (ran) {
        app.log.info('已执行计划每日 Hermes 备份');
      }
    } catch (e) {
      app.log.error(e, '计划备份失败');
    }
  };
  void tick();
  setInterval(() => void tick(), 60 * 60 * 1000);
}
