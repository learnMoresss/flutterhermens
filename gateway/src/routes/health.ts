import type { FastifyPluginAsync } from 'fastify';

import { dashboardSessionsEnabled, loadConfig } from '../config.js';
import { getCreateAppSkillDiagnostics } from '../admin/create-app-prompt.js';
import { probeHermesApiHealth } from '../hermes/api-server.js';
import { probeHermesDashboard } from '../hermes/dashboard.js';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => {
    const cfg = loadConfig();
    const [hermesApiOk, hermesDashboardOk] = await Promise.all([
      probeHermesApiHealth(cfg),
      probeHermesDashboard(cfg),
    ]);

    return {
      status: 'ok',
      service: 'hermes-gateway',
      version: cfg.GATEWAY_VERSION,
      mode: 'hermes-api-proxy',
      hermesApiOrigin: cfg.HERMES_API_ORIGIN,
      hermesApiReachable: hermesApiOk,
      hermesDashboardOrigin: cfg.HERMES_DASHBOARD_ORIGIN ?? null,
      hermesDashboardReachable: dashboardSessionsEnabled(cfg) ? hermesDashboardOk : null,
      sessionsApiEnabled: dashboardSessionsEnabled(cfg),
      createAppSkill: getCreateAppSkillDiagnostics(),
    };
  });
};
