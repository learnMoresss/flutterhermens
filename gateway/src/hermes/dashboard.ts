import type { AppConfig } from '../config.js';

function dashBase(cfg: AppConfig): string {
  const origin = cfg.HERMES_DASHBOARD_ORIGIN?.trim();
  if (!origin) throw new Error('HERMES_DASHBOARD_ORIGIN not configured');
  return origin.replace(/\/$/, '');
}

export async function fetchHermesDashboard(
  cfg: AppConfig,
  pathname: string,
  init?: RequestInit,
): Promise<Response> {
  const token = cfg.HERMES_DASHBOARD_TOKEN?.trim();
  if (!token) throw new Error('HERMES_DASHBOARD_TOKEN not configured');
  const path = pathname.startsWith('/') ? pathname : `/${pathname}`;
  return fetch(`${dashBase(cfg)}${path}`, {
    ...init,
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Hermes-Session-Token': token,
      ...init?.headers,
    },
  });
}

export async function probeHermesDashboard(cfg: AppConfig): Promise<boolean> {
  if (!cfg.HERMES_DASHBOARD_ORIGIN?.trim() || !cfg.HERMES_DASHBOARD_TOKEN?.trim()) {
    return false;
  }
  try {
    const res = await fetchHermesDashboard(cfg, '/api/status', {
      signal: AbortSignal.timeout(2800),
    });
    return res.ok;
  } catch {
    return false;
  }
}
