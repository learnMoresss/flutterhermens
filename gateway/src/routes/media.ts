import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import type { FastifyPluginAsync, FastifyRequest } from 'fastify';

import {
  buildMediaServeUrl,
  decodePathParam,
  fileDisplayName,
  guessMimeType,
  isImagePath,
  isPathAllowed,
  resolveBareMediaName,
  resolveReadableFile,
  verifyAccessToken,
} from '../admin/media-serve.js';
import { sendReadableFile } from '../admin/file-range.js';

async function hasJwtAuth(req: FastifyRequest): Promise<boolean> {
  try {
    await req.jwtVerify();
    return true;
  } catch {
    return false;
  }
}

export const mediaRoutes: FastifyPluginAsync = async (app) => {
  app.get<{
    Querystring: { path?: string; exp?: string; sig?: string };
  }>('/v1/media/serve', async (req, reply) => {
    const encoded = req.query.path?.trim();
    if (!encoded) {
      return reply.code(400).send({ message: '缺少 path 参数' });
    }

    const absPath = decodePathParam(encoded);
    if (!absPath) {
      return reply.code(400).send({ message: 'path 参数无效' });
    }

    const jwtOk = await hasJwtAuth(req);
    if (!jwtOk) {
      const exp = Number.parseInt(req.query.exp ?? '', 10);
      const sig = req.query.sig?.trim() ?? '';
      if (!verifyAccessToken(absPath, exp, sig)) {
        return reply.code(403).send({ message: '链接无效或已过期' });
      }
    }

    const fileInfo = resolveReadableFile(absPath);
    if (!fileInfo) {
      return reply.code(404).send({ message: '文件不存在或不可访问' });
    }

    const filePath = fileInfo.path;
    const mime = guessMimeType(filePath);
    const name = fileDisplayName(filePath);
    const inline =
      isImagePath(filePath) ||
      mime.startsWith('text/') ||
      mime.startsWith('audio/') ||
      mime.startsWith('video/');

    return sendReadableFile(req, reply, {
      filePath,
      stat: fileInfo.stat,
      mime,
      filename: name,
      inline,
    });
  });

  app.post<{ Body: { path?: string } }>('/v1/media/sign', async (req, reply) => {
    if (!(await hasJwtAuth(req))) {
      return reply.code(401).send({ message: '未授权：请先登录' });
    }

    const rawPath = req.body?.path?.trim();
    if (!rawPath) {
      return reply.code(400).send({ message: '缺少 path' });
    }

    let absPath = rawPath;
    if (rawPath.startsWith('MEDIA:')) {
      const inner = rawPath.slice('MEDIA:'.length).trim();
      if (inner.toLowerCase().startsWith('file://')) {
        try {
          absPath = fileURLToPath(inner);
        } catch {
          return reply.code(400).send({ message: 'MEDIA 路径无效' });
        }
      } else {
        const resolved = resolveBareMediaName(inner);
        if (!resolved) {
          return reply.code(404).send({ message: '媒体文件未找到' });
        }
        absPath = resolved;
      }
    } else if (rawPath.toLowerCase().startsWith('file://')) {
      try {
        absPath = fileURLToPath(rawPath);
      } catch {
        return reply.code(400).send({ message: 'file:// 路径无效' });
      }
    } else if (rawPath.startsWith('/')) {
      try {
        absPath = realpathSync(rawPath);
      } catch {
        absPath = rawPath;
      }
      if (!isPathAllowed(absPath)) {
        return reply.code(403).send({ message: '路径不在允许范围内' });
      }
    }

    const url = buildMediaServeUrl(absPath);
    if (!url) {
      return reply.code(403).send({ message: '路径不在允许范围内或文件不可访问' });
    }
    return { url };
  });
};
