import type { AppConfig } from '../config.js';

function apiBase(cfg: AppConfig): string {
  return cfg.HERMES_API_ORIGIN.replace(/\/$/, '');
}

export async function fetchHermesApi(
  cfg: AppConfig,
  pathname: string,
  init?: RequestInit,
): Promise<Response> {
  const path = pathname.startsWith('/') ? pathname : `/${pathname}`;
  return fetch(`${apiBase(cfg)}${path}`, {
    ...init,
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${cfg.HERMES_API_SERVER_KEY}`,
      ...init?.headers,
    },
  });
}

export async function proxyChatCompletions(
  cfg: AppConfig,
  body: unknown,
  signal?: AbortSignal,
): Promise<Response> {
  return fetchHermesApi(cfg, '/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'text/event-stream, application/json',
    },
    body: JSON.stringify(body),
    signal,
  });
}

export async function probeHermesApiHealth(cfg: AppConfig): Promise<boolean> {
  try {
    const res = await fetch(`${apiBase(cfg)}/health`, {
      method: 'GET',
      signal: AbortSignal.timeout(2800),
    });
    return res.ok;
  } catch {
    return false;
  }
}
