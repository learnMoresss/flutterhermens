import { Transform } from 'node:stream';

import { rewriteSseDataLine } from './media-url-rewrite.js';

/** 按行改写 SSE，保留未完成行的缓冲。 */
export class SseMediaRewriteTransform extends Transform {
  private carry = '';

  constructor() {
    super({ decodeStrings: false });
  }

  override _transform(
    chunk: Buffer,
    _encoding: BufferEncoding,
    callback: (error?: Error | null) => void,
  ): void {
    this.carry += chunk.toString('utf-8');
    const lines = this.carry.split('\n');
    this.carry = lines.pop() ?? '';

    for (const line of lines) {
      const out = rewriteSseDataLine(line);
      this.push(`${out}\n`);
    }
    callback();
  }

  override _flush(callback: (error?: Error | null) => void): void {
    if (this.carry.length > 0) {
      this.push(rewriteSseDataLine(this.carry));
    }
    callback();
  }
}
