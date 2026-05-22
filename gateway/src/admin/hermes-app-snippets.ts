/** HermesApp 调用示例（单一数据源：HTML 注入 + create-app 提示 + snippets.js） */

import {
  buildCreateAppDelegationBrief,
  CREATE_APP_DELEGATION_MARKER,
  CREATE_APP_FOLDER_ANTI_PATTERNS,
} from './create-app-delegation.js';
import { getProjectsRoot, getPublicBaseUrlForProjects } from './projects-manager.js';
export type HermesAppSnippet = {
  title: string;
  when: string;
  code: string;
};

export const HERMES_APP_ANTI_PATTERNS: string[] = [
  '禁止 drag-drop / dropzone 作为唯一上传方式（App WebView 不可用）',
  '禁止隐藏 <input type="file"> 作为 App 内主入口（Android WebView 点击常失效）',
  '禁止依赖 getUserMedia / MediaRecorder（WebView 权限不可靠）',
  '禁止仅用 <a download> 导出（须 HermesApp.saveFile / shareFile）',
  '禁止把 saveFile 当分享用：saveFile=保存到相册/下载目录，shareFile=系统分享面板',
  '禁止手写 window.__HERMES_PROJECT__ 或重复引入 host.js（Gateway 已注入）',
  '禁止在 JS 里写 slug 裸标识符（如 image-compressor），必须用字符串 "image-compressor"',
  '禁止内联 PNG 压缩库时写错语法（如 new Uint8Array(n),-1）',
];

export const HERMES_APP_SAVE_MATRIX = [
  { category: 'image', mime: 'image/*', saveFile: '相册', shareFile: '系统分享面板' },
  { category: 'video', mime: 'video/*', saveFile: '相册', shareFile: '系统分享面板' },
  { category: 'audio', mime: 'audio/*', saveFile: 'Downloads/文件', shareFile: '系统分享面板' },
  { category: 'document', mime: 'pdf/doc/xls/ppt/epub…', saveFile: 'Downloads/文件', shareFile: '系统分享面板' },
  { category: 'archive', mime: 'zip/rar/7z…', saveFile: 'Downloads/文件', shareFile: '系统分享面板' },
  { category: 'text', mime: 'txt/csv/json/html…', saveFile: 'Downloads/文件', shareFile: '系统分享面板' },
  { category: 'other', mime: '任意', saveFile: 'Downloads/文件', shareFile: '系统分享面板' },
];

export const HERMES_APP_SNIPPETS: Record<string, HermesAppSnippet> = {
  init: {
    title: '初始化（每个页面开头必写）',
    when: '任何使用 HermesApp 的 static/dynamic 前端',
    code: `(async function () {
  await HermesApp.ready();
  if (!HermesApp.isAvailable) {
    document.body.innerHTML =
      '<p style="padding:24px">请在 Hermes Mobile App「应用 Tab」内打开</p>';
    return;
  }
  const project = HermesApp.getProject(); // { slug, apiBase, hostApi }
  // ↓ 在此绑定按钮、渲染 UI
})();`,
  },
  pickImage: {
    title: '选择图片（相册/相机）',
    when: '图片上传、压缩器、头像、扫码前选图',
    code: `document.getElementById('pickBtn').addEventListener('click', async function () {
  const r = await HermesApp.pickImage({
    source: 'gallery', // 'camera' 打开相机
    compress: false,     // true 时原生先压图
    upload: false,       // true 时上传 Gateway，返回 r.url
  });
  if (!r.ok) {
    if (r.code !== 'CANCELLED') await HermesApp.toast(r.message || '选图失败');
    return;
  }
  // r.base64, r.mimeType, r.filename, r.size
  const img = new Image();
  img.onload = function () { /* 用 img 或 canvas 处理 */ };
  img.src = 'data:' + r.mimeType + ';base64,' + r.base64;
});`,
  },
  pickFile: {
    title: '选择任意文件（PDF/CSV/音频/压缩包等）',
    when: '非图片场景；可限制扩展名',
    code: `const r = await HermesApp.pickFile({
  maxBytes: 50 * 1024 * 1024,
  upload: false,
  allowedExtensions: ['pdf', 'csv', 'txt', 'zip', 'mp3', 'm4a'],
});
if (!r.ok) {
  if (r.code !== 'CANCELLED') await HermesApp.toast(r.message || '选文件失败');
  return;
}
// r.base64, r.mimeType, r.filename, r.size, r.category`,
  },
  pickVideo: {
    title: '选择视频',
    when: '视频处理、上传',
    code: `const r = await HermesApp.pickVideo({ source: 'gallery', upload: false });
if (!r.ok && r.code !== 'CANCELLED') await HermesApp.toast(r.message || '选视频失败');`,
  },
  saveFile: {
    title: '保存文件（不弹分享面板）',
    when: '用户点「保存」：按类型自动路由',
    code: `// 图片/视频 → 相册；PDF/音频/zip/txt 等 → Downloads（Android）或文件（iOS）
// 可选 picker:true 让用户自选保存位置
const r = await HermesApp.saveFile({
  base64: fileBase64,
  filename: 'report.pdf',
  mimeType: 'application/pdf',
  // picker: true,
});
if (!r.ok) await HermesApp.toast(r.message || '保存失败');
// r.destination: gallery-image | gallery-video | downloads | documents | picker
// r.category: image | video | audio | document | archive | text | other`,
  },
  shareFile: {
    title: '分享任意文件（系统分享面板）',
    when: '用户点「分享」：微信/Drive/邮件等；支持图片/PDF/音频/视频/zip',
    code: `const r = await HermesApp.shareFile({
  base64: fileBase64,
  filename: 'report.pdf',
  mimeType: 'application/pdf',
  title: '分析报告',
});
if (!r.ok) await HermesApp.toast(r.message || '分享失败');`,
  },
  shareText: {
    title: '分享文字/链接',
    when: '分享 URL 或文本，不含文件',
    code: `await HermesApp.share({ title: '标题', text: '说明', url: 'https://…' });`,
  },
  uploadBlob: {
    title: '上传 base64 到 Gateway（≤8MB）',
    when: '需要公网 URL 给后端 API 或 Hermes 视觉模型',
    code: `const r = await HermesApp.uploadBlob({
  base64: fileBase64,
  filename: 'photo.jpg',
  mimeType: 'image/jpeg',
});
if (!r.ok) return HermesApp.toast(r.message || '上传失败');
// r.url, r.uploadId — 传给 fetch(project.apiBase + '/analyze', { body: JSON.stringify({ url: r.url }) })`,
  },
  toast: {
    title: '轻提示',
    when: '操作反馈，勿用 alert',
    code: `await HermesApp.toast('已保存');`,
  },
  recordAudio: {
    title: '录音',
    when: '语音备忘、语音输入',
    code: `await HermesApp.recordAudio.start({ maxDurationSec: 120 });
// … 用户说话 …
const r = await HermesApp.recordAudio.stop({ upload: false });
if (!r.ok) return HermesApp.toast(r.message || '录音失败');
// r.base64, mimeType: 'audio/mp4'`,
  },
  imageCompressor: {
    title: '图片压缩器完整最小页（推荐复制改 UI）',
    when: '用户要图片压缩、缩略图、格式转换',
    code: `// 结构：#pickZone → pickImage → canvas 压缩
// 两个按钮：saveFile（保存到相册）+ shareFile（系统分享）
// 参考：docs/hermes-projects/_examples/image-compressor/public/index.html`,
  },
};

export function buildHermesAppSnippetsPayload(): {
  version: number;
  antiPatterns: string[];
  folderAntiPatterns: string[];
  delegationMarker: string;
  delegationBrief: string;
  saveMatrix: typeof HERMES_APP_SAVE_MATRIX;
  snippets: Record<string, HermesAppSnippet>;
} {
  const projectsRoot = getProjectsRoot();
  const publicBase = getPublicBaseUrlForProjects();
  return {
    version: 3,
    antiPatterns: HERMES_APP_ANTI_PATTERNS,
    folderAntiPatterns: CREATE_APP_FOLDER_ANTI_PATTERNS,
    delegationMarker: CREATE_APP_DELEGATION_MARKER,
    delegationBrief: buildCreateAppDelegationBrief({
      projectsRoot,
      publicBase,
      mode: 'create',
      hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
    }),
    saveMatrix: HERMES_APP_SAVE_MATRIX,
    snippets: HERMES_APP_SNIPPETS,
  };
}

export function buildHermesAppSnippetsScript(): string {
  const json = JSON.stringify(buildHermesAppSnippetsPayload(), null, 2);
  return `/** HermesApp 调用示例（Gateway 注入，勿删；编写业务 script 时复制 snippets 内 code） */\nwindow.__HERMES_APP_SNIPPETS__ = ${json};\n`;
}

export function buildHermesAppInjectComment(): string {
  const lines = [
    'HermesApp 宿主 API — Gateway 自动注入，编写 public/index.html 时必遵：',
    '1) 等 HermesApp.ready()  2) 检查 isAvailable  3) 用 pickImage/pickFile，勿 drag-drop',
    '4) saveFile=保存(相册/下载) shareFile=分享  5) __HERMES_APP_SNIPPETS__.saveMatrix 查类型路由',
    '6) 勿手写 __HERMES_PROJECT__ / 勿重复引入 host.js',
    '7) 委派 OpenCode/Claude 等外部工具时须遵守 __HERMES_APP_SNIPPETS__.delegationBrief',
  ];
  return `<!--\n  ${lines.join('\n  ')}\n-->`;
}

/** 注入 create-app / 目标项目 system 提示（Markdown） */
export function buildHermesAppSnippetsMarkdown(): string {
  const parts: string[] = [
    '## HermesApp 调用示例（复制即用，勿自创 drag-drop / file input 方案）',
    '',
    '### 禁止',
    ...HERMES_APP_ANTI_PATTERNS.map((s) => `- ${s}`),
    '',
  ];
  for (const sn of Object.values(HERMES_APP_SNIPPETS)) {
    parts.push(`### ${sn.title}`, '', `**何时用**：${sn.when}`, '', '```javascript', sn.code, '```', '');
  }
  parts.push(
    '## 委派外部编程工具 — Delegation Brief（复制给 OpenCode / Claude Code）',
    '',
    buildCreateAppDelegationBrief({
      projectsRoot: getProjectsRoot(),
      publicBase: getPublicBaseUrlForProjects(),
      mode: 'create',
      hermesAppAntiPatterns: HERMES_APP_ANTI_PATTERNS,
    }),
  );
  return parts.join('\n').trim();
}
