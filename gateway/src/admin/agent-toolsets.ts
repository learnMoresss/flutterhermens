import { existsSync } from 'node:fs';

import { hermesPath, readTextFile, writeTextFile } from './agent-home.js';

export interface ToolsetInfo {
  key: string;
  label: string;
  description: string;
  enabled: boolean;
}

const TOOLSET_DEFS: { key: string; label: string; description: string }[] = [
  { key: 'web', label: '网页搜索', description: '搜索互联网获取实时信息' },
  { key: 'browser', label: '浏览器', description: '自动化浏览网页并交互' },
  { key: 'terminal', label: '终端', description: '执行 Shell 命令' },
  { key: 'file', label: '文件', description: '读写本地文件' },
  { key: 'code_execution', label: '代码执行', description: '在沙箱中运行代码' },
  { key: 'vision', label: '视觉', description: '理解图片与视觉内容' },
  { key: 'image_gen', label: '图像生成', description: '生成图片' },
  { key: 'tts', label: '语音合成', description: '文字转语音' },
  { key: 'skills', label: '技能', description: '调用已安装技能' },
  { key: 'memory', label: '记忆', description: '长期记忆读写' },
  { key: 'session_search', label: '会话搜索', description: '搜索历史会话' },
  { key: 'clarify', label: '澄清', description: '向用户澄清需求' },
  { key: 'delegation', label: '委派', description: '委派子任务给其他 Agent' },
  { key: 'cronjob', label: '计划任务', description: '定时执行任务' },
  { key: 'moa', label: '混合专家', description: '多模型协作（MoA）' },
  { key: 'todo', label: '待办', description: '任务列表与进度跟踪' },
];

function parseEnabledToolsets(configContent: string): Set<string> {
  const enabled = new Set<string>();
  const lines = configContent.split('\n');
  let inPlatformToolsets = false;
  let inCli = false;

  for (const line of lines) {
    const trimmed = line.trimEnd();
    if (/^\s*platform_toolsets\s*:/.test(trimmed)) {
      inPlatformToolsets = true;
      inCli = false;
      continue;
    }
    if (inPlatformToolsets && /^\s+cli\s*:/.test(trimmed)) {
      inCli = true;
      continue;
    }
    if (inPlatformToolsets && /^\S/.test(trimmed) && !/^\s*$/.test(trimmed)) {
      inPlatformToolsets = false;
      inCli = false;
      continue;
    }
    if (inCli && /^\s{4}\S/.test(trimmed) && !/^\s{4,}-/.test(trimmed)) {
      inCli = false;
      continue;
    }
    if (inCli) {
      const match = trimmed.match(/^\s+-\s+["']?(\w+)["']?/);
      if (match) enabled.add(match[1]);
    }
  }
  return enabled;
}

export function listToolsets(): ToolsetInfo[] {
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) {
    return TOOLSET_DEFS.map((d) => ({ ...d, enabled: true }));
  }
  const content = readTextFile(configFile);
  const enabledSet = parseEnabledToolsets(content);
  if (enabledSet.size === 0 && !content.includes('platform_toolsets')) {
    return TOOLSET_DEFS.map((d) => ({ ...d, enabled: true }));
  }
  return TOOLSET_DEFS.map((d) => ({ ...d, enabled: enabledSet.has(d.key) }));
}

export function setToolsetEnabled(key: string, enabled: boolean): boolean {
  const configFile = hermesPath('config.yaml');
  if (!existsSync(configFile)) return false;
  if (!TOOLSET_DEFS.some((d) => d.key === key)) return false;

  const content = readTextFile(configFile);
  const currentEnabled = parseEnabledToolsets(content);
  if (enabled) currentEnabled.add(key);
  else currentEnabled.delete(key);

  const toolsetLines = Array.from(currentEnabled)
    .sort()
    .map((t) => `      - ${t}`)
    .join('\n');
  const newSection = `  cli:\n${toolsetLines}`;

  if (content.includes('platform_toolsets')) {
    const lines = content.split('\n');
    const result: string[] = [];
    let inPlatformToolsets = false;
    let inCli = false;
    let cliInserted = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trimEnd();
      if (/^\s*platform_toolsets\s*:/.test(trimmed)) {
        inPlatformToolsets = true;
        result.push(line);
        continue;
      }
      if (inPlatformToolsets && /^\s+cli\s*:/.test(trimmed)) {
        inCli = true;
        result.push(newSection);
        cliInserted = true;
        continue;
      }
      if (inCli) {
        if (/^\s+-\s/.test(trimmed)) continue;
        if (/^\s{4}\S/.test(trimmed) || /^\S/.test(trimmed) || trimmed === '') {
          inCli = false;
          result.push(line);
          continue;
        }
        continue;
      }
      if (inPlatformToolsets && /^\S/.test(trimmed) && trimmed !== '') {
        inPlatformToolsets = false;
        if (!cliInserted) {
          result.push(newSection);
          cliInserted = true;
        }
      }
      result.push(line);
    }
    writeTextFile(configFile, result.join('\n'));
  } else {
    writeTextFile(configFile, `${content.trimEnd()}\n\nplatform_toolsets:\n${newSection}\n`);
  }
  return true;
}
