import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

/** 与 CTranslate2 NLLB-200 / FLORES-200 对齐的语言项 */
export class TranslateLanguageOption {
  label: string = '';
  nllbCode: string = '';
  isoCode: string = '';
}

interface LanguageJsonRow {
  nllbCode: string;
  label: string;
  isoCode: string;
}

/**
 * CTranslate2 本身不内置语言表；接 NLLB-200 时使用 FLORES-200 语言码。
 * 列表来自 entry/src/main/resources/rawfile/flores200_languages.json
 */
export class TranslateLanguages {
  private static choices: TranslateLanguageOption[] = TranslateLanguages.buildFallback();
  private static loadPromise: Promise<void> | null = null;

  private static buildFallback(): TranslateLanguageOption[] {
    const rows: LanguageJsonRow[] = [
      { nllbCode: 'zho_Hans', label: '中文（简体）', isoCode: 'zh' },
      { nllbCode: 'eng_Latn', label: '英语', isoCode: 'en' },
      { nllbCode: 'rus_Cyrl', label: '俄语', isoCode: 'ru' },
      { nllbCode: 'jpn_Jpan', label: '日语', isoCode: 'ja' },
      { nllbCode: 'kor_Hang', label: '韩语', isoCode: 'ko' },
      { nllbCode: 'fra_Latn', label: '法语', isoCode: 'fr' },
      { nllbCode: 'deu_Latn', label: '德语', isoCode: 'de' },
      { nllbCode: 'spa_Latn', label: '西班牙语', isoCode: 'es' },
      { nllbCode: 'arb_Arab', label: '阿拉伯语', isoCode: 'ar' },
      { nllbCode: 'ukr_Cyrl', label: '乌克兰语', isoCode: 'uk' },
    ];
    return TranslateLanguages.parseJsonArray(rows);
  }

  private static parseJsonArray(raw: LanguageJsonRow[]): TranslateLanguageOption[] {
    const out: TranslateLanguageOption[] = [];
    for (let i = 0; i < raw.length; i++) {
      const row = raw[i];
      const opt = new TranslateLanguageOption();
      opt.nllbCode = row.nllbCode;
      opt.label = row.label.length > 0 ? row.label : opt.nllbCode;
      opt.isoCode = row.isoCode;
      if (opt.nllbCode.length > 0) {
        out.push(opt);
      }
    }
    return out;
  }

  static getLanguageChoices(): TranslateLanguageOption[] {
    return TranslateLanguages.choices;
  }

  static findByNllbCode(code: string): TranslateLanguageOption | undefined {
    const list = TranslateLanguages.choices;
    for (let i = 0; i < list.length; i++) {
      if (list[i].nllbCode === code) {
        return list[i];
      }
    }
    return undefined;
  }

  static labelForNllbCode(code: string): string {
    return TranslateLanguages.findByNllbCode(code)?.label ?? code;
  }

  /** 底栏/键盘上方语言 pill：过长时只保留前 6 字 + 「...」，避免两侧同时过长撑出屏幕 */
  static compactLabelForLangBar(label: string): string {
    const t = label.trim();
    const max = 6;
    if (t.length <= max) {
      return t;
    }
    return `${t.substring(0, max)}...`;
  }

  static isoForNllbCode(nllbCode: string): string {
    return TranslateLanguages.findByNllbCode(nllbCode)?.isoCode ?? 'en';
  }

  static findByIsoCode(iso: string): TranslateLanguageOption | undefined {
    const list = TranslateLanguages.choices;
    for (let i = 0; i < list.length; i++) {
      if (list[i].isoCode === iso) {
        return list[i];
      }
    }
    return undefined;
  }

  static nllbForIsoCode(iso: string): string {
    return TranslateLanguages.findByIsoCode(iso)?.nllbCode ?? iso;
  }

  static labelForIsoCode(iso: string): string {
    const hit = TranslateLanguages.findByIsoCode(iso);
    if (hit !== undefined) {
      return hit.label;
    }
    return TranslateLanguages.labelForDetectedCode(iso);
  }

  /** 与 Android homeLanguageChoices / ML Kit 支持的 9 种语言一致 */
  static getHomeLanguageChoices(): TranslateLanguageOption[] {
    const homeIsos: string[] = ['en', 'zh', 'ar', 'ja', 'ko', 'fr', 'de', 'es', 'ru'];
    const out: TranslateLanguageOption[] = [];
    for (let i = 0; i < homeIsos.length; i++) {
      const opt = TranslateLanguages.findByIsoCode(homeIsos[i]);
      if (opt !== undefined) {
        out.push(opt);
      }
    }
    if (out.length > 0) {
      return out;
    }
    return TranslateLanguages.buildFallback();
  }

  static isoInHomeChoices(iso: string): boolean {
    const home = TranslateLanguages.getHomeLanguageChoices();
    for (let i = 0; i < home.length; i++) {
      if (home[i].isoCode === iso) {
        return true;
      }
    }
    return false;
  }

  /** 首页底栏当前选中的两种语言（源语言纠正弹窗仅展示这两项） */
  static getPairLanguageChoices(sourceNllb: string, targetNllb: string): TranslateLanguageOption[] {
    const out: TranslateLanguageOption[] = [];
    const src = TranslateLanguages.findByNllbCode(sourceNllb);
    const tgt = TranslateLanguages.findByNllbCode(targetNllb);
    if (src !== undefined) {
      out.push(src);
    }
    if (tgt !== undefined) {
      let duplicate = false;
      for (let i = 0; i < out.length; i++) {
        if (out[i].nllbCode === tgt.nllbCode) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        out.push(tgt);
      }
    }
    return out;
  }

  /** 拍照翻译底栏目标语（与 Android cameraTargetChoices） */
  static getCameraTargetChoices(): TranslateLanguageOption[] {
    return TranslateLanguages.getHomeLanguageChoices();
  }

  static labelForDetectedCode(iso: string): string {
    if (iso === 'zh') {
      return '中文';
    }
    if (iso === 'en') {
      return '英语';
    }
    if (iso === 'ar') {
      return '阿拉伯语';
    }
    if (iso === 'ja') {
      return '日语';
    }
    if (iso === 'ko') {
      return '韩语';
    }
    if (iso === 'fr') {
      return '法语';
    }
    if (iso === 'de') {
      return '德语';
    }
    if (iso === 'es') {
      return '西班牙语';
    }
    if (iso === 'ru') {
      return '俄语';
    }
    return iso.toUpperCase();
  }

  /** 从 rawfile 加载完整 FLORES/NLLB 语言表（失败则保留 fallback） */
  static loadFromRawfile(context: common.UIAbilityContext): Promise<void> {
    if (TranslateLanguages.loadPromise !== null) {
      return TranslateLanguages.loadPromise;
    }
    TranslateLanguages.loadPromise = (async () => {
      try {
        const rawFile = await context.resourceManager.getRawFileContent('flores200_languages.json');
        const text = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(rawFile);
        const parsed = JSON.parse(text) as LanguageJsonRow[];
        if (parsed.length > 0) {
          TranslateLanguages.choices = TranslateLanguages.parseJsonArray(parsed);
        }
      } catch (_e) {
        // 保留 buildFallback
      }
    })();
    return TranslateLanguages.loadPromise;
  }
}
