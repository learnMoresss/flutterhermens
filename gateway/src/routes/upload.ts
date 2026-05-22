import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import multipart from '@fastify/multipart';

import { sendReadableFile } from '../admin/file-range.js';
import { buildUploadFileUrl, verifyUploadAccess } from '../admin/media-serve.js';
import { getUploadMeta, saveUpload } from '../admin/upload-store.js';
import { existsSync, statSync } from 'node:fs';
import { getUploadFilePath } from '../admin/upload-store.js';

const MAX_BYTES = 8 * 1024 * 1024;

async function requireJwt(req: FastifyRequest, reply: FastifyReply): Promise<boolean> {
  try {
    await req.jwtVerify();
    return true;
  } catch {
    reply.code(401).send({ message: '未授权：请先登录' });
    return false;
  }
}

function canAccessUpload(
  req: FastifyRequest<{ Params: { id: string }; Querystring: { access?: string; exp?: string } }>,
): boolean {
  const access = req.query.access?.trim();
  const exp = Number.parseInt(req.query.exp ?? '', 10);
  if (access && Number.isFinite(exp)) {
    return verifyUploadAccess(req.params.id, exp, access);
  }
  return false;
}

export const uploadRoutes: FastifyPluginAsync = async (app) => {
  await app.register(multipart, {
    limits: { fileSize: MAX_BYTES, files: 1 },
  });

  app.post('/v1/upload', async (req, reply) => {
    if (!(await requireJwt(req, reply))) return;

    const part = await req.file();
    if (!part) {
      return reply.code(400).send({ message: '未收到文件' });
    }

    const buffer = await part.toBuffer();
    if (buffer.length > MAX_BYTES) {
      return reply.code(413).send({ message: `文件过大（最大 ${Math.floor(MAX_BYTES / 1024 / 1024)}MB）` });
    }

    const filename = part.filename || 'upload.bin';
    const mimeType = part.mimetype || 'application/octet-stream';
    const record = saveUpload(filename, mimeType, buffer);

    const payload: Record<string, unknown> = {
      id: record.id,
      filename: record.filename,
      mimeType: record.mimeType,
      size: record.size,
      downloadPath: `/v1/files/${record.id}`,
    };

    const publicUrl = buildUploadFileUrl(record.id);
    if (publicUrl) {
      payload.url = publicUrl;
    }

    return payload;
  });

  app.get<{ Params: { id: string }; Querystring: { access?: string; exp?: string } }>(
    '/v1/files/:id',
    async (req, reply) => {
      const signedOk = canAccessUpload(req);
      if (!signedOk && !(await requireJwt(req, reply))) return;

      const meta = getUploadMeta(req.params.id);
      if (!meta) {
        return reply.code(404).send({ message: '文件不存在' });
      }
      const filePath = getUploadFilePath(req.params.id);
      if (!filePath) {
        return reply.code(404).send({ message: '文件不存在' });
      }
      const stat = statSync(filePath);
      const inline =
        meta.mimeType.startsWith('image/') ||
        meta.mimeType.startsWith('audio/') ||
        meta.mimeType.startsWith('video/') ||
        meta.mimeType.startsWith('text/');

      return sendReadableFile(req, reply, {
        filePath,
        stat,
        mime: meta.mimeType,
        filename: meta.filename,
        inline,
      });
    },
  );
};
