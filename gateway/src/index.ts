import jwt from '@fastify/jwt';

import Fastify from 'fastify';

import { logCreateAppSkillStatus } from './admin/create-app-prompt.js';
import { startHermesAdminScheduler } from './admin/scheduler.js';

import { loadConfig } from './config.js';

import { adminAgentRoutes } from './routes/admin-agent.js';
import { adminJobsRoutes } from './routes/admin-jobs.js';
import { adminDockerRoutes } from './routes/admin-docker.js';
import { adminHermesRoutes } from './routes/admin-hermes.js';
import { adminMessageGatewayRoutes } from './routes/admin-message-gateway.js';
import { wsInfoRoutes } from './routes/ws-info.js';

import { authRoutes } from './routes/auth.js';
import { chatRoutes } from './routes/chat.js';
import { mediaRoutes } from './routes/media.js';
import { uploadRoutes } from './routes/upload.js';

import { healthRoutes } from './routes/health.js';

import { loginRoutes } from './routes/login.js';

import { sessionsRoutes } from './routes/sessions.js';

import { projectsRoutes } from './routes/projects.js';
import { hermesAppRoutes } from './routes/hermes-app.js';
import { setupDiscoverRoutes } from './routes/setup-discover.js';



async function main() {

  const cfg = loadConfig();



  const app = Fastify({

    logger: cfg.NODE_ENV !== 'test',

    requestTimeout: 120_000,

  });



  await app.register(jwt, { secret: cfg.JWT_SECRET });



  await app.register(healthRoutes);

  await app.register(setupDiscoverRoutes);

  await app.register(loginRoutes);

  await app.register(authRoutes);

  await app.register(uploadRoutes);

  await app.register(mediaRoutes);

  await app.register(chatRoutes);

  await app.register(projectsRoutes);

  await app.register(hermesAppRoutes);

  await app.register(sessionsRoutes);

  await app.register(adminHermesRoutes, { prefix: '/v1/admin/hermes' });
  await app.register(adminAgentRoutes, { prefix: '/v1/admin/agent' });
  await app.register(adminJobsRoutes, { prefix: '/v1/admin/jobs' });
  await app.register(adminDockerRoutes, { prefix: '/v1/admin/docker' });
  await app.register(adminMessageGatewayRoutes, { prefix: '/v1/admin/message-gateway' });
  await app.register(wsInfoRoutes);



  startHermesAdminScheduler(app);

  logCreateAppSkillStatus(app.log);

  await app.listen({ port: cfg.PORT, host: cfg.HOST });

  app.log.info(`hermes-gateway listening on http://${cfg.HOST}:${cfg.PORT}`);

}



main().catch((err) => {

  console.error(err);

  process.exit(1);

});


