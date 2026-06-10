import { TranslateLanguages } from './TranslateLanguages';

/** 与 Android CameraTranslateActivity.countOcrUnits / ocrMetaSummaryLine 对齐 */
export class OcrMeta {
  static countUnits(detectedCode: string, text: string): number {
    if (text.length === 0) {
      return 0;
    }
    let n = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if (detectedCode === 'zh' && ch >= 0x4E00 && ch <= 0x9FFF) {
        n++;
      } else if (detectedCode === 'ja' &&
        ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3040 && ch <= 0x309F) || (ch >= 0x30A0 && ch <= 0x30FF))) {
        n++;
      } else if (detectedCode === 'ko' && ch >= 0xAC00 && ch <= 0xD7AF) {
        n++;
      } else if ((detectedCode === 'en' || detectedCode === 'fr' || detectedCode === 'de' || detectedCode === 'es') &&
        ((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122))) {
        n++;
      } else if (detectedCode === 'ar' && ch >= 0x0600 && ch <= 0x06FF) {
        n++;
      } else if (detectedCode === 'ru' && ch >= 0x0400 && ch <= 0x04FF) {
        n++;
      }
    }
    if (n === 0 && text.trim().length > 0) {
      return text.length;
    }
    return n;
  }

  static summaryLine(detectedCode: string, text: string): string {
    const label = TranslateLanguages.labelForDetectedCode(detectedCode);
    const n = OcrMeta.countUnits(detectedCode, text);
    if (detectedCode === 'zh') {
      return `${label} · 识别 ${n} 个汉字`;
    }
    if (detectedCode === 'en') {
      return `${label} · 识别 ${n} 个字母`;
    }
    if (detectedCode === 'ar') {
      return `${label} · 识别 ${n} 个阿拉伯文字`;
    }
    if (detectedCode === 'ja') {
      return `${label} · 识别 ${n} 个字符`;
    }
    if (detectedCode === 'ko') {
      return `${label} · 识别 ${n} 个谚文`;
    }
    if (detectedCode === 'ru') {
      return `${label} · 识别 ${n} 个西里尔字母`;
    }
    if (detectedCode === 'fr' || detectedCode === 'de' || detectedCode === 'es') {
      return `${label} · 识别 ${n} 个字母`;
    }
    return `${label} · 识别 ${n} 个字符`;
  }
}
