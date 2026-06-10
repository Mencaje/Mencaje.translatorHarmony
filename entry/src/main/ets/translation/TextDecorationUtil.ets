/**
 * 表情符号、颜文字等装饰性片段：翻译时原样保留，语种检测与 TTS 时忽略。
 * NLLB/SentencePiece 会把未知 emoji 编成英文子词，故不可整段送入模型。
 */

export enum TextSegmentKind {
  TEXT = 0,
  DECORATION = 1,
}

export interface TextSegment {
  kind: TextSegmentKind;
  content: string;
}

interface CodePointInfo {
  cp: number;
  charLen: number;
}

export class TextDecorationUtil {
  /** 按原文顺序拆分可译文本与装饰片段 */
  static splitSegments(text: string): TextSegment[] {
    const segments: TextSegment[] = [];
    let i = 0;
    while (i < text.length) {
      const kaomojiLen = TextDecorationUtil.measureKaomojiRun(text, i);
      if (kaomojiLen > 0) {
        TextDecorationUtil.pushSegment(segments, TextSegmentKind.DECORATION,
          text.substring(i, i + kaomojiLen));
        i += kaomojiLen;
        continue;
      }
      const cpInfo = TextDecorationUtil.codePointAt(text, i);
      const kind = TextDecorationUtil.isDecorationCodePoint(cpInfo.cp) ?
        TextSegmentKind.DECORATION : TextSegmentKind.TEXT;
      let j = i + cpInfo.charLen;
      while (j < text.length) {
        const km = TextDecorationUtil.measureKaomojiRun(text, j);
        if (km > 0) {
          break;
        }
        const next = TextDecorationUtil.codePointAt(text, j);
        const nextKind = TextDecorationUtil.isDecorationCodePoint(next.cp) ?
          TextSegmentKind.DECORATION : TextSegmentKind.TEXT;
        if (nextKind !== kind) {
          break;
        }
        j += next.charLen;
      }
      TextDecorationUtil.pushSegment(segments, kind, text.substring(i, j));
      i = j;
    }
    return segments;
  }

  /** 去掉装饰片段，供语种启发式使用 */
  static stripForLanguageDetection(text: string): string {
    const segs = TextDecorationUtil.splitSegments(text);
    let out = '';
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].kind === TextSegmentKind.TEXT) {
        out += segs[i].content;
      }
    }
    return out;
  }

  /** 去掉装饰片段并规整空白，供 TTS 朗读 */
  static stripForTts(text: string): string {
    const segs = TextDecorationUtil.splitSegments(text);
    let out = '';
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].kind === TextSegmentKind.TEXT) {
        out += segs[i].content;
      }
    }
    return out.replace(/\s+/g, ' ').trim();
  }

  /** 是否仅有装饰、无字母/数字等可译内容 */
  static isDecorationOnly(text: string): boolean {
    if (text.trim().length === 0) {
      return false;
    }
    return TextDecorationUtil.stripForLanguageDetection(text).trim().length === 0;
  }

  /**
   * 分段翻译后按原顺序拼回；装饰片段不送模型。
   */
  static async mergeTranslated(
    text: string,
    translatePart: (part: string) => Promise<string>
  ): Promise<string> {
    const segs = TextDecorationUtil.splitSegments(text);
    let out = '';
    for (let i = 0; i < segs.length; i++) {
      const seg = segs[i];
      if (seg.kind === TextSegmentKind.DECORATION) {
        out += seg.content;
        continue;
      }
      const part = seg.content;
      if (part.trim().length === 0) {
        out += part;
        continue;
      }
      out += await translatePart(part);
    }
    return out;
  }

  private static pushSegment(segments: TextSegment[], kind: TextSegmentKind, content: string): void {
    if (content.length === 0) {
      return;
    }
    const last = segments.length > 0 ? segments[segments.length - 1] : null;
    if (last !== null && last.kind === kind) {
      last.content += content;
    } else {
      const seg: TextSegment = { kind: kind, content: content };
      segments.push(seg);
    }
  }

  private static codePointAt(text: string, index: number): CodePointInfo {
    const c = text.charCodeAt(index);
    if (c >= 0xD800 && c <= 0xDBFF && index + 1 < text.length) {
      const c2 = text.charCodeAt(index + 1);
      if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
        const surrogate: CodePointInfo = {
          cp: (c - 0xD800) * 0x400 + (c2 - 0xDC00) + 0x10000,
          charLen: 2
        };
        return surrogate;
      }
    }
    const single: CodePointInfo = { cp: c, charLen: 1 };
    return single;
  }

  private static isLetterLike(cp: number): boolean {
    if (cp <= 0x7F) {
      return (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A);
    }
    if ((cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0x3040 && cp <= 0x30FF) ||
      (cp >= 0xAC00 && cp <= 0xD7AF)) {
      return true;
    }
    if (cp >= 0x0400 && cp <= 0x04FF) {
      return true;
    }
    if (cp >= 0x0600 && cp <= 0x06FF) {
      return true;
    }
    if (cp >= 0x0370 && cp <= 0x03FF) {
      return true;
    }
    return false;
  }

  private static isDecorationCodePoint(cp: number): boolean {
    if (cp === 0x200D || cp === 0xFE0E || cp === 0xFE0F) {
      return true;
    }
    if (cp >= 0x1F3FB && cp <= 0x1F3FF) {
      return true;
    }
    if (cp >= 0x1F1E6 && cp <= 0x1F1FF) {
      return true;
    }
    if (cp === 0x00A9 || cp === 0x00AE || cp === 0x203C || cp === 0x2049 ||
      cp === 0x2122 || cp === 0x2139) {
      return true;
    }
    if (cp >= 0x2194 && cp <= 0x2199) {
      return true;
    }
    if (cp === 0x21A9 || cp === 0x21AA) {
      return true;
    }
    if (cp >= 0x231A && cp <= 0x231B) {
      return true;
    }
    if (cp === 0x2328 || cp === 0x23CF) {
      return true;
    }
    if (cp >= 0x23E9 && cp <= 0x23F3) {
      return true;
    }
    if (cp >= 0x23F8 && cp <= 0x23FA) {
      return true;
    }
    if (cp === 0x24C2) {
      return true;
    }
    if (cp >= 0x25AA && cp <= 0x25FE) {
      return true;
    }
    if (cp >= 0x2600 && cp <= 0x27BF) {
      return true;
    }
    if (cp >= 0x2934 && cp <= 0x2935) {
      return true;
    }
    if (cp >= 0x2B05 && cp <= 0x2B55) {
      return true;
    }
    if (cp === 0x3030 || cp === 0x303D) {
      return true;
    }
    if (cp === 0x3297 || cp === 0x3299) {
      return true;
    }
    if (cp >= 0x1F000 && cp <= 0x1FAFF) {
      return true;
    }
    if (cp >= 0xE0100 && cp <= 0xE01EF) {
      return true;
    }
    if (cp >= 0xE000 && cp <= 0xF8FF) {
      return true;
    }
    return false;
  }

  /** 从 index 起若为颜文字/符号装饰则返回 run 长度，否则 0 */
  private static measureKaomojiRun(text: string, index: number): number {
    if (index >= text.length) {
      return 0;
    }
    const first = TextDecorationUtil.codePointAt(text, index);
    if (TextDecorationUtil.isLetterLike(first.cp) || TextDecorationUtil.isDecorationCodePoint(first.cp)) {
      return 0;
    }
    if (!TextDecorationUtil.isKaomojiChar(first.cp)) {
      return 0;
    }
    let j = index + first.charLen;
    let hasParen = first.cp === 0x28 || first.cp === 0x29 || first.cp === 0xFF08 || first.cp === 0xFF09;
    while (j < text.length) {
      const info = TextDecorationUtil.codePointAt(text, j);
      if (TextDecorationUtil.isLetterLike(info.cp) || TextDecorationUtil.isDecorationCodePoint(info.cp)) {
        break;
      }
      if (!TextDecorationUtil.isKaomojiChar(info.cp)) {
        break;
      }
      if (info.cp === 0x28 || info.cp === 0x29 || info.cp === 0xFF08 || info.cp === 0xFF09) {
        hasParen = true;
      }
      j += info.charLen;
    }
    const len = j - index;
    if (len < 2) {
      return 0;
    }
    if (!hasParen && len < 4) {
      return 0;
    }
    return len;
  }

  private static isKaomojiChar(cp: number): boolean {
    if (cp === 0x09 || cp === 0x0A || cp === 0x0D || cp === 0x20) {
      return true;
    }
    if (cp <= 0x7F) {
      const punct = '()[]{}<>|\\/~^*_-=+.:;!?@#$%&`"\',';
      for (let i = 0; i < punct.length; i++) {
        if (cp === punct.charCodeAt(i)) {
          return true;
        }
      }
      return false;
    }
    if (cp >= 0x3000 && cp <= 0x303F) {
      return true;
    }
    if (cp >= 0xFF00 && cp <= 0xFFEF) {
      return true;
    }
    if (cp === 0x00B0 || cp === 0x25A1 || cp === 0x25CB) {
      return true;
    }
    if (cp >= 0x2500 && cp <= 0x257F) {
      return true;
    }
    return false;
  }
}
