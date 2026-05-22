import {

  buildUploadFileUrl,

  getInternalBaseUrl,

  getPublicBaseUrl,

} from './media-serve.js';

import { getUploadMeta, readUploadBuffer } from './upload-store.js';



/**

 * App → Gateway：http(s) 公网 URL（Flutter 预览）

 * Gateway → Hermes（url 模式，官方推荐）：内网可拉取的 http URL，供 vision_analyze 工具使用

 * Gateway → Hermes（inline 模式）：data:image base64，仅适用于原生支持 vision 的模型

 *

 * 文本模型不会处理对话里的 base64，需 vision_analyze + URL：

 * https://hermes-agent.nousresearch.com/docs/user-guide/features/vision

 * https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server

 */



/** Hermes API Server 请求体约 1MB 上限，inline base64 留余量 */

const MAX_INLINE_RAW_BYTES = 720 * 1024;



type HermesImageMode = 'url' | 'inline';



function getHermesImageMode(): HermesImageMode {

  const raw = process.env.GATEWAY_HERMES_IMAGE_MODE?.trim().toLowerCase();

  return raw === 'inline' ? 'inline' : 'url';

}



function extractUploadId(url: string): string | null {

  const trimmed = url.trim();

  try {

    const u = new URL(trimmed, 'http://localhost');

    const match = u.pathname.match(/\/v1\/files\/([^/]+)$/i);

    const id = match?.[1];

    return id ? decodeURIComponent(id) : null;

  } catch {

    const relative = trimmed.match(/\/v1\/files\/([^/?#]+)/i);

    const id = relative?.[1];

    return id ? decodeURIComponent(id) : null;

  }

}



function inlineUploadAsDataUrl(fileId: string): string | null {

  const meta = getUploadMeta(fileId);

  const buffer = readUploadBuffer(fileId);

  if (!meta || !buffer || buffer.length === 0) return null;

  if (buffer.length > MAX_INLINE_RAW_BYTES) {

    console.warn(

      `[chat-attachments] upload ${fileId} too large for Hermes inline (${buffer.length} bytes); ` +

        'compress image or raise HERMES_MAX_REQUEST_BYTES on Hermes',

    );

    return null;

  }

  const mime = meta.mimeType.toLowerCase().startsWith('image/')

    ? meta.mimeType

    : 'image/jpeg';

  return `data:${mime};base64,${buffer.toString('base64')}`;

}



/** Hermes 宿主机可拉取的上传 URL（vision_analyze 官方路径） */

function resolveGatewayUploadUrlForHermes(fileId: string): string | null {

  if (!getUploadMeta(fileId)) return null;

  const internal = buildUploadFileUrl(fileId, getInternalBaseUrl());

  if (internal) return internal;

  return buildUploadFileUrl(fileId, getPublicBaseUrl());

}



function resolveGatewayUploadForHermes(fileId: string): string | null {

  if (getHermesImageMode() === 'inline') {

    return inlineUploadAsDataUrl(fileId);

  }

  return resolveGatewayUploadUrlForHermes(fileId);

}



function warnVisionMiss(url: string, reason: string): void {

  console.warn(

    `[chat-attachments] vision resolve failed (${reason}): ${url.slice(0, 120)}`,

  );

}



export function normalizeHermesImageUrl(url: string): string | null {

  const trimmed = url.trim();

  if (!trimmed) return trimmed;



  const mode = getHermesImageMode();



  if (trimmed.startsWith('data:image/')) {

    if (mode === 'url') {

      warnVisionMiss(trimmed, 'data URL ignored in url mode; Hermes vision_analyze needs http URL');

      return null;

    }

    const comma = trimmed.indexOf(',');

    if (comma > 0) {

      const b64 = trimmed.slice(comma + 1);

      const rawLen = Math.floor((b64.length * 3) / 4);

      if (rawLen > MAX_INLINE_RAW_BYTES) {

        warnVisionMiss(trimmed, `data URL too large (${rawLen} bytes)`);

      }

    }

    return trimmed;

  }



  const uploadId = extractUploadId(trimmed);

  if (uploadId) {

    const resolved = resolveGatewayUploadForHermes(uploadId);

    if (resolved) return resolved;

    warnVisionMiss(trimmed, `upload ${uploadId} not found or not readable`);

  }



  if (/^https?:\/\//i.test(trimmed)) {

    const publicBase = getPublicBaseUrl();

    if (publicBase && trimmed.startsWith(publicBase)) {

      const id = extractUploadId(trimmed);

      if (id) {

        const resolved = resolveGatewayUploadForHermes(id);

        if (resolved) return resolved;

        warnVisionMiss(trimmed, `gateway upload ${id} not readable`);

      }

    }

    if (mode === 'url') {

      return trimmed;

    }

    if (trimmed.includes('/v1/files/') || trimmed.includes('/v1/media/serve')) {

      warnVisionMiss(trimmed, 'gateway media URL could not be resolved');

    }

    return trimmed;

  }



  if (trimmed.startsWith('/v1/files/')) {

    const id = extractUploadId(trimmed);

    if (id) {

      const resolved = resolveGatewayUploadForHermes(id);

      if (resolved) return resolved;

      warnVisionMiss(trimmed, `relative upload ${id} not readable`);

    }

  }



  return trimmed;

}



type ContentPart = Record<string, unknown>;



function rewriteContent(content: unknown): unknown {

  if (typeof content === 'string') return content;

  if (!Array.isArray(content)) return content;



  return content

    .map((part) => {

      if (!part || typeof part !== 'object') return part;

      const p = part as ContentPart;

      if (p.type !== 'image_url') return part;



      const imageUrl = p.image_url;

      if (!imageUrl || typeof imageUrl !== 'object') return part;

      const rawUrl = (imageUrl as { url?: unknown }).url;

      if (typeof rawUrl !== 'string' || !rawUrl.trim()) return part;



      const resolved = normalizeHermesImageUrl(rawUrl);

      if (!resolved) return null;



      return {

        ...p,

        image_url: {

          ...(imageUrl as Record<string, unknown>),

          url: resolved,

          detail: (imageUrl as { detail?: unknown }).detail ?? 'high',

        },

      };

    })

    .filter((part) => part != null);

}



export function normalizeChatImagesForHermes(messages: unknown[]): unknown[] {

  return messages.map((message) => {

    if (!message || typeof message !== 'object') return message;

    const m = message as { role?: unknown; content?: unknown };

    if (!('content' in m)) return message;

    return {

      ...m,

      content: rewriteContent(m.content),

    };

  });

}


