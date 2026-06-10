import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MyMemoryLanguageCodes } from './MyMemoryLanguageCodes';

interface MyMemoryResponse {
  responseData?: MyMemoryResponseData;
  responseStatus?: number;
  responseDetails?: string;
  matches?: MyMemoryMatchRow[];
}

interface MyMemoryResponseData {
  translatedText?: string;
}

interface MyMemoryMatchRow {
  translation?: string;
  match?: number;
  segment?: string;
  quality?: number | string;
  /** MyMemory 机器翻译条目 reference 常为 "Machine Translation." */
  reference?: string;
}

/**
 * 在线翻译后端（MyMemory 公共 API）。
 * 鸿蒙暂无与 Android ML Kit 等价的系统离线翻译 Kit；在 CTranslate2 NAPI 就绪前用此实现完整句子翻译。
 * 接入本机模型后由 OnDeviceTranslator 优先走离线路径。
 */
export class OnlineTranslateProvider {
  private static readonly MAX_CHUNK_CHARS: number = 450;
  private static readonly HTTP_TIMEOUT_MS: number = 60000;
  private static readonly CACHE_MAX_ENTRIES: number = 128;
  /** 429 时最多重试次数（含首次） */
  private static readonly RATE_LIMIT_ATTEMPTS: number = 4;
  private static readonly RATE_LIMIT_DELAYS_MS: number[] = [0, 2500, 6000, 12000];
  private static readonly resultCache: Map<string, string> = new Map();

  static async translate(text: string, sourceIso: string, targetIso: string): Promise<string> {
    const body = text.trim();
    if (body.length === 0) {
      throw new Error('empty text');
    }
    if (sourceIso === targetIso) {
      return text;
    }
    const cacheKey = OnlineTranslateProvider.buildCacheKey(body, sourceIso, targetIso);
    const cached = OnlineTranslateProvider.resultCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    let result = '';
    if (body.indexOf('\n') < 0) {
      result = await OnlineTranslateProvider.translateChunk(body, sourceIso, targetIso);
    } else {
      const lines = text.split('\n');
      const outs: string[] = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.trim().length === 0) {
          outs.push(line);
        } else {
          outs.push(await OnlineTranslateProvider.translateChunk(line, sourceIso, targetIso));
        }
      }
      result = outs.join('\n');
    }
    OnlineTranslateProvider.putCache(cacheKey, result);
    return result;
  }

  private static buildCacheKey(text: string, sourceIso: string, targetIso: string): string {
    return `${sourceIso.trim().toLowerCase()}|${targetIso.trim().toLowerCase()}|${text}`;
  }

  private static putCache(key: string, value: string): void {
    if (value.length === 0) {
      return;
    }
    while (OnlineTranslateProvider.resultCache.size >= OnlineTranslateProvider.CACHE_MAX_ENTRIES) {
      const keys = OnlineTranslateProvider.resultCache.keys();
      const first = keys.next();
      if (first.done) {
        break;
      }
      OnlineTranslateProvider.resultCache.delete(first.value);
    }
    OnlineTranslateProvider.resultCache.set(key, value);
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  private static isRateLimitError(message: string): boolean {
    const m = message.toLowerCase();
    return m.indexOf('429') >= 0 ||
      m.indexOf('quota') >= 0 ||
      m.indexOf('too many') >= 0 ||
      m.indexOf('rate limit') >= 0;
  }

  private static rateLimitUserMessage(): string {
    return '在线翻译请求过于频繁（服务器返回 429），请等待 1～2 分钟后再试';
  }

  private static async translateChunk(text: string, sourceIso: string, targetIso: string): Promise<string> {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return text;
    }
    if (trimmed.length <= OnlineTranslateProvider.MAX_CHUNK_CHARS) {
      return await OnlineTranslateProvider.requestMyMemory(trimmed, sourceIso, targetIso);
    }
    const parts: string[] = [];
    let start = 0;
    while (start < trimmed.length) {
      const end = Math.min(start + OnlineTranslateProvider.MAX_CHUNK_CHARS, trimmed.length);
      const slice = trimmed.substring(start, end);
      parts.push(await OnlineTranslateProvider.requestMyMemory(slice, sourceIso, targetIso));
      start = end;
    }
    return parts.join('');
  }

  private static async requestMyMemory(text: string, sourceIso: string, targetIso: string): Promise<string> {
    let lastMsg = '';
    const attempts = OnlineTranslateProvider.RATE_LIMIT_ATTEMPTS;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const delay = OnlineTranslateProvider.RATE_LIMIT_DELAYS_MS[attempt] ?? 12000;
      if (delay > 0) {
        await OnlineTranslateProvider.sleep(delay);
      }
      try {
        return await OnlineTranslateProvider.requestMyMemoryOnce(text, sourceIso, targetIso);
      } catch (e) {
        const msg = (e as Error).message ?? 'network translate failed';
        lastMsg = msg;
        if (!OnlineTranslateProvider.isRateLimitError(msg) || attempt >= attempts - 1) {
          if (OnlineTranslateProvider.isRateLimitError(msg)) {
            throw new Error(OnlineTranslateProvider.rateLimitUserMessage());
          }
          throw new Error(msg);
        }
      }
    }
    if (OnlineTranslateProvider.isRateLimitError(lastMsg)) {
      throw new Error(OnlineTranslateProvider.rateLimitUserMessage());
    }
    throw new Error(lastMsg.length > 0 ? lastMsg : 'network translate failed');
  }

  private static async requestMyMemoryOnce(
    text: string,
    sourceIso: string,
    targetIso: string
  ): Promise<string> {
    const src = MyMemoryLanguageCodes.toMyMemoryCode(sourceIso);
    const tgt = MyMemoryLanguageCodes.toMyMemoryCode(targetIso);
    const q = encodeURIComponent(text);
    const url = `https://api.mymemory.translated.net/get?q=${q}&langpair=${src}|${tgt}`;
    const client = http.createHttp();
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: OnlineTranslateProvider.HTTP_TIMEOUT_MS,
        readTimeout: OnlineTranslateProvider.HTTP_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      if (resp.responseCode === 429) {
        throw new Error('HTTP 429');
      }
      if (resp.responseCode !== 200) {
        throw new Error(`HTTP ${resp.responseCode}`);
      }
      const raw = resp.result as string;
      const parsed = JSON.parse(raw) as MyMemoryResponse;
      const status = parsed.responseStatus ?? 0;
      if (status === 429) {
        throw new Error('HTTP 429');
      }
      if (status !== 200) {
        const detail = parsed.responseDetails ?? 'translate failed';
        if (OnlineTranslateProvider.isRateLimitError(detail)) {
          throw new Error('HTTP 429');
        }
        throw new Error(detail);
      }
      const primary = parsed.responseData?.translatedText?.trim() ?? '';
      const out = OnlineTranslateProvider.pickBestMyMemoryTranslation(
        primary, parsed.matches ?? [], text, targetIso);
      if (out.length === 0) {
        throw new Error('empty translation result');
      }
      return OnlineTranslateProvider.decodeHtmlEntities(out);
    } catch (e) {
      const be = e as BusinessError;
      const msg = be.message ?? (e as Error).message ?? 'network translate failed';
      throw new Error(msg);
    } finally {
      client.destroy();
    }
  }

  /**
   * MyMemory 优先返回语料库「高匹配」条目，zh→uk 等语种对常误中字幕/注释（如俄语括号句）。
   * 在候选里按目标语质量分选最佳译文。
   */
  private static pickBestMyMemoryTranslation(
    primary: string,
    matches: MyMemoryMatchRow[],
    sourceText: string,
    targetIso: string
  ): string {
    const candidates: MyMemoryMatchRow[] = [];
    const seen = new Set<string>();
    const addRow = (row: MyMemoryMatchRow): void => {
      const t = row.translation?.trim() ?? '';
      if (t.length === 0 || seen.has(t)) {
        return;
      }
      seen.add(t);
      candidates.push(row);
    };
    for (let i = 0; i < matches.length; i++) {
      addRow(matches[i]);
    }
    if (primary.length > 0) {
      addRow({ translation: primary });
    }
    if (candidates.length === 0) {
      return '';
    }
    let best = candidates[0].translation?.trim() ?? '';
    let bestScore = OnlineTranslateProvider.scoreTranslationCandidate(
      candidates[0], sourceText, targetIso);
    for (let i = 1; i < candidates.length; i++) {
      const score = OnlineTranslateProvider.scoreTranslationCandidate(
        candidates[i], sourceText, targetIso);
      if (score > bestScore) {
        bestScore = score;
        best = candidates[i].translation?.trim() ?? '';
      }
    }
    return best;
  }

  private static scoreTranslationCandidate(
    row: MyMemoryMatchRow,
    sourceText: string,
    targetIso: string
  ): number {
    const t = row.translation?.trim() ?? '';
    if (t.length === 0) {
      return -100;
    }
    const src = sourceText.trim();
    const srcLen = src.length;
    const tgtLen = t.length;
    let score = 0;

    if (row.match !== undefined) {
      score += row.match * 4;
    }
    const ref = row.reference?.trim() ?? '';
    if (ref.indexOf('Machine Translation') >= 0) {
      score += 8;
    }
    const q = row.quality;
    if (typeof q === 'number' && q >= 70) {
      score += 5;
    }
    if (row.segment !== undefined && row.segment.trim() === src) {
      score += 10;
    }

    const tgt = targetIso.trim().toLowerCase();
    if (tgt === 'zh' || tgt === 'zh-hant') {
      if (/[\u4e00-\u9fff]/.test(t)) {
        score += 6;
      }
      if (srcLen > 12 && tgtLen < srcLen * 0.35) {
        score -= 20;
      }
      if (/^(嘿|嗨|哈|哟|啊|噢|哦|嗯)(\s*(嘿|嗨|哈|哟|啊|噢|哦|嗯))*$/.test(t.replace(/\s/g, ''))) {
        score -= 18;
      }
    }
    if (tgt === 'uk') {
      if (/[\u0456\u0457\u0491]/.test(t)) {
        score += 4;
      }
      if (/[\u0400-\u04FF]/.test(t)) {
        score += 1;
      }
      if (/тагальск|говорят\s+на/i.test(t)) {
        score -= 12;
      }
      if (/^\([^)]+\):?\s*$/.test(t)) {
        score -= 10;
      }
    }
    if (tgt === 'ru' && /[\u0400-\u04FF]/.test(t)) {
      score += 1;
    }
    return score;
  }

  /** MyMemory 有时返回 HTML 实体 */
  private static decodeHtmlEntities(s: string): string {
    return s
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }
}
