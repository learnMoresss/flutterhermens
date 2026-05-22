import { existsSync } from 'node:fs';

import { hermesPath, readTextFile, writeTextFile } from './agent-home.js';

const DEFAULT_SOUL = `你是 Hermes，一位乐于助人的 AI 助手。你友好、博学，始终热心帮助用户。

你沟通清晰简洁。接到任务时会逐步思考并说明理由。你诚实面对自身局限，必要时主动请用户澄清。

你在提供协助的同时注重安全与责任，尊重用户隐私，谨慎处理敏感信息。
`;

export function readSoul(): string {
  const soulFile = hermesPath('SOUL.md');
  if (!existsSync(soulFile)) return '';
  return readTextFile(soulFile);
}

export function writeSoul(content: string): void {
  writeTextFile(hermesPath('SOUL.md'), content);
}

export function resetSoul(): string {
  writeSoul(DEFAULT_SOUL);
  return DEFAULT_SOUL;
}
