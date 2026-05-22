import { createReadStream } from 'node:fs';
import type { Stats } from 'node:fs';
import type { FastifyReply, FastifyRequest } from 'fastify';

export type FileStreamReplyOptions = {
  filePath: string;
  stat: Stats;
  mime: string;
  filename: string;
  inline: boolean;
};

function parseRangeHeader(rangeHeader: string, size: number): { start: number; end: number } | null {
  const m = /^bytes=(\d*)-(\d*)$/i.exec(rangeHeader.trim());
  if (!m) return null;

  let start = m[1] ? Number.parseInt(m[1], 10) : 0;
  let end = m[2] ? Number.parseInt(m[2], 10) : size - 1;

  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  if (m[1] === '' && m[2] !== '') {
    const suffix = Number.parseInt(m[2], 10);
    if (Number.isNaN(suffix)) return null;
    start = Math.max(size - suffix, 0);
    end = size - 1;
  }
  if (start < 0 || end < start || start >= size) return null;
  end = Math.min(end, size - 1);
  return { start, end };
}

/**
 * 支持 HTTP Range（206），供 ExoPlayer / video_player 流式播放 MP4。
 * 必须 return 此函数结果，否则 Fastify 会提前结束响应导致空 body。
 */
export function sendReadableFile(
  req: FastifyRequest,
  reply: FastifyReply,
  opts: FileStreamReplyOptions,
): FastifyReply {
  const { filePath, stat, mime, filename, inline } = opts;
  const size = stat.size;

  if (size <= 0) {
    return reply.code(404).send({ message: '文件为空' });
  }

  reply.header('Accept-Ranges', 'bytes');
  reply.header('Content-Type', mime);
  reply.header(
    'Content-Disposition',
    `${inline ? 'inline' : 'attachment'}; filename="${encodeURIComponent(filename)}"`,
  );

  const rangeHeader = req.headers.range;
  if (rangeHeader && typeof rangeHeader === 'string') {
    const parsed = parseRangeHeader(rangeHeader, size);
    if (!parsed) {
      return reply.code(416).header('Content-Range', `bytes */${size}`).send();
    }
    const { start, end } = parsed;
    const chunk = end - start + 1;
    return reply
      .code(206)
      .header('Content-Range', `bytes ${start}-${end}/${size}`)
      .header('Content-Length', chunk)
      .send(createReadStream(filePath, { start, end }));
  }

  return reply.header('Content-Length', size).send(createReadStream(filePath));
}
