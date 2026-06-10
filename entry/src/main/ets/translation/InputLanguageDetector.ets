import { TextLanguageHeuristic } from './TextLanguageHeuristic';
import { TextDecorationUtil } from './TextDecorationUtil';

/**
 * 首页输入框源语种推断。
 * 与 Android 不同：纠正/自动识别仅在本页选中的「原文↔译文」两种语言之间判定（见 detectForHomePair）。
 */
export class InputLanguageDetector {
  /** 全量启发式（拍照等场景可用） */
  static detectForHomeInput(text: string): string {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return 'en';
    }
    return TextLanguageHeuristic.guessIsoCode(trimmed);
  }

  /**
   * 首页翻译：只在用户选定的两种语言之间识别（与 Android buildHomeTranslatePlan 配合）。
   * 例如栏上为「中文 + 英语」时，输入 hello → en；输入你好 → zh；不会出现韩语等第三语种。
   */
  static detectForHomePair(text: string, prefSourceIso: string, prefTargetIso: string): string {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return prefSourceIso;
    }
    const forDetect = TextDecorationUtil.stripForLanguageDetection(trimmed).trim();
    if (forDetect.length === 0) {
      return prefSourceIso;
    }
    if (prefSourceIso === prefTargetIso) {
      return prefSourceIso;
    }
    const raw = TextLanguageHeuristic.guessIsoCode(forDetect);
    if (raw === prefSourceIso || raw === prefTargetIso) {
      return raw;
    }
    const heuristic = TextLanguageHeuristic.guessIsoCode(forDetect);
    if (heuristic === prefSourceIso || heuristic === prefTargetIso) {
      return heuristic;
    }
    if (InputLanguageDetector.looksMostlyCjk(forDetect)) {
      return prefSourceIso;
    }
    if (InputLanguageDetector.looksMostlyLatin(forDetect)) {
      return prefTargetIso;
    }
    return prefSourceIso;
  }

  private static looksMostlyCjk(text: string): boolean {
    let cjk = 0;
    let letters = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3040 && ch <= 0x30FF) || (ch >= 0xAC00 && ch <= 0xD7AF)) {
        cjk++;
      }
      if ((ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)) {
        letters++;
      }
    }
    const len = Math.max(text.length, 1);
    return cjk * 2 >= len;
  }

  private static looksMostlyLatin(text: string): boolean {
    let latin = 0;
    let total = 0;
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if (ch <= 32) {
        continue;
      }
      total++;
      if ((ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)) {
        latin++;
      }
    }
    return total > 0 && latin * 2 >= total;
  }
}
