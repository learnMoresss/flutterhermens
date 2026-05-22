import type { FastifyPluginAsync } from 'fastify';

import { dashboardSessionsEnabled, loadConfig } from '../config.js';
import { probeHermesApiHealth } from '../hermes/api-server.js';
import { probeHermesDashboard } from '../hermes/dashboard.js';

const DOCKER_BACKUP_NOTE =
  'Docker：容器**不能**直接访问任意宿主机路径；只有 **volume 挂载**进容器、且 .env 中路径与挂载点一致时，备份/打包才可用。' +
  'Hermes API Server 须在宿主机 `~/.hermes/.env` 启用 API_SERVER_ENABLED 并 `hermes gateway` 运行。';

/** App 初始化用：无需登录；探测 Hermes API Server / Dashboard 可达性。 */
export const setupDiscoverRoutes: FastifyPluginAsync = async (app) => {
  app.get('/v1/setup/discover', async () => {
    const cfg = loadConfig();
    const [apiOk, dashOk] = await Promise.all([
      probeHermesApiHealth(cfg),
      dashboardSessionsEnabled(cfg) ? probeHermesDashboard(cfg) : Promise.resolve(false),
    ]);

    const probeDetail = apiOk
      ? `Hermes API Server 可达：${cfg.HERMES_API_ORIGIN}`
      : `Hermes API Server 不可达：${cfg.HERMES_API_ORIGIN}（请确认宿主机已启用 API_SERVER_ENABLED 且端口 8642 监听）`;

    return {
      hermesApiOrigin: cfg.HERMES_API_ORIGIN,
      hermesApiReachable: apiOk,
      hermesDashboardOrigin: cfg.HERMES_DASHBOARD_ORIGIN ?? null,
      hermesDashboardReachable: dashboardSessionsEnabled(cfg) ? dashOk : null,
      sessionsApiEnabled: dashboardSessionsEnabled(cfg),
      hermesProbeDetail: probeDetail,
      backupSource: cfg.HERMES_BACKUP_SOURCE,
      backupDir: cfg.HERMES_BACKUP_DIR,
      gatewayVersion: cfg.GATEWAY_VERSION,
      backupDockerNote: DOCKER_BACKUP_NOTE,
      // 兼容旧 App 字段
      hermesOriginEffective: cfg.HERMES_API_ORIGIN,
      hermesOriginProbed: apiOk ? cfg.HERMES_API_ORIGIN : null,
      hermesOriginMismatch: false,
      hermesReachable: apiOk,
    };
  });
};
