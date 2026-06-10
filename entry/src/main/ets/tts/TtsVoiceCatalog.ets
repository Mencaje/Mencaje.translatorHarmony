import { TtsPiperVoiceCatalog } from './TtsPiperVoiceCatalog';

/**
 * 朗读语言目录（与 SileroModelPaths / native 声线一致）。
 *
 * 程序员备忘（勿在 UI 展示分区标题）：
 * - 已支持朗读 core 34 种：zh, ja, ru, en, uk, pl, pt, ka, de, da, el, fa, fi, cy, fr, hi, hu, is, it, kk, lb, lv, ml, ne, nl, no, ro, sk, sl, sr, sv, sw, tr, vi（无 es；ky/mk/sq/eo 已移除：仅 RHVoice/GPL-2.0，用户要求不编入）
 * - Piper 扩展 3 种：见 TtsPiperVoiceCatalog.ENTRIES（ar, ca, cs；其余 Piper 语种已并入 core）
 *   日语 ja 走 piper-plus-ja 专用包；其余 Piper 语种走 silero_tts/piper/<iso>/
 */
export type TtsEngineKind = 'summertts' | 'piper' | 'rhvoice';

export interface TtsVoiceCatalogEntry {
  iso: string;
  label: string;
  engine: TtsEngineKind;
  /** RHVoice voice_profile 目录名（仅 rhvoice） */
  rhvoiceProfile?: string;
  /** Piper 模型键，如 de_DE-thorsten-medium（仅 piper，ja 除外走专用包） */
  piperVoiceKey?: string;
}

function buildEntries(): TtsVoiceCatalogEntry[] {
  // --- 已支持朗读（34）SummerTTS / piper-plus-ja / Piper ---
  const core: TtsVoiceCatalogEntry[] = [
    { iso: 'zh', label: '中文', engine: 'summertts' },
    { iso: 'ja', label: '日语', engine: 'piper' },
    { iso: 'ru', label: '俄语', engine: 'piper', piperVoiceKey: 'ru_RU-denis-medium' },
    { iso: 'en', label: '英语', engine: 'piper', piperVoiceKey: 'en_US-lessac-medium' },
    { iso: 'uk', label: '乌克兰语', engine: 'piper', piperVoiceKey: 'uk_UA-ukrainian_tts-medium' },
    { iso: 'pl', label: '波兰语', engine: 'piper', piperVoiceKey: 'pl_PL-darkman-medium' },
    { iso: 'pt', label: '葡萄牙语', engine: 'piper', piperVoiceKey: 'pt_BR-faber-medium' },
    { iso: 'ka', label: '格鲁吉亚语', engine: 'piper', piperVoiceKey: 'ka_GE-natia-medium' },
    { iso: 'de', label: '德语', engine: 'piper', piperVoiceKey: 'de_DE-thorsten-medium' },
    { iso: 'da', label: '丹麦语', engine: 'piper', piperVoiceKey: 'da_DK-talesyntese-medium' },
    { iso: 'el', label: '希腊语', engine: 'piper', piperVoiceKey: 'el_GR-rapunzelina-low' },
    { iso: 'fa', label: '波斯语', engine: 'piper', piperVoiceKey: 'fa_IR-ganji-medium' },
    { iso: 'fi', label: '芬兰语', engine: 'piper', piperVoiceKey: 'fi_FI-harri-medium' },
    { iso: 'cy', label: '威尔士语', engine: 'piper', piperVoiceKey: 'cy_GB-gwryw_gogleddol-medium' },
    { iso: 'fr', label: '法语', engine: 'piper', piperVoiceKey: 'fr_FR-siwis-medium' },
    { iso: 'hi', label: '印地语', engine: 'piper', piperVoiceKey: 'hi_IN-pratham-medium' },
    { iso: 'hu', label: '匈牙利语', engine: 'piper', piperVoiceKey: 'hu_HU-anna-medium' },
    { iso: 'is', label: '冰岛语', engine: 'piper', piperVoiceKey: 'is_IS-salka-medium' },
    { iso: 'it', label: '意大利语', engine: 'piper', piperVoiceKey: 'it_IT-paola-medium' },
    { iso: 'kk', label: '哈萨克语', engine: 'piper', piperVoiceKey: 'kk_KZ-issai-high' },
    { iso: 'lb', label: '卢森堡语', engine: 'piper', piperVoiceKey: 'lb_LU-marylux-medium' },
    { iso: 'lv', label: '拉脱维亚语', engine: 'piper', piperVoiceKey: 'lv_LV-aivars-medium' },
    { iso: 'ml', label: '马拉雅拉姆语', engine: 'piper', piperVoiceKey: 'ml_IN-meera-medium' },
    { iso: 'ne', label: '尼泊尔语', engine: 'piper', piperVoiceKey: 'ne_NP-google-medium' },
    { iso: 'nl', label: '荷兰语', engine: 'piper', piperVoiceKey: 'nl_NL-pim-medium' },
    { iso: 'no', label: '挪威语', engine: 'piper', piperVoiceKey: 'no_NO-talesyntese-medium' },
    { iso: 'ro', label: '罗马尼亚语', engine: 'piper', piperVoiceKey: 'ro_RO-mihai-medium' },
    { iso: 'sk', label: '斯洛伐克语', engine: 'piper', piperVoiceKey: 'sk_SK-lili-medium' },
    { iso: 'sl', label: '斯洛文尼亚语', engine: 'piper', piperVoiceKey: 'sl_SI-artur-medium' },
    { iso: 'sr', label: '塞尔维亚语', engine: 'piper', piperVoiceKey: 'sr_RS-serbski_institut-medium' },
    { iso: 'sv', label: '瑞典语', engine: 'piper', piperVoiceKey: 'sv_SE-lisa-medium' },
    { iso: 'sw', label: '斯瓦希里语', engine: 'piper', piperVoiceKey: 'sw_CD-lanfrica-medium' },
    { iso: 'tr', label: '土耳其语', engine: 'piper', piperVoiceKey: 'tr_TR-dfki-medium' },
    { iso: 'vi', label: '越南语', engine: 'piper', piperVoiceKey: 'vi_VN-vais1000-medium' },
  ];
  // --- Piper 官方库扩展（3），见 TtsPiperVoiceCatalog；UI 与 core 同一列表，无分区标题 ---
  const piperExtras: TtsVoiceCatalogEntry[] = [];
  const catalog = TtsPiperVoiceCatalog.ENTRIES;
  for (let i = 0; i < catalog.length; i++) {
    piperExtras.push({
      iso: catalog[i].iso,
      label: catalog[i].label,
      engine: 'piper',
      piperVoiceKey: catalog[i].voiceKey,
    });
  }
  return core.concat(piperExtras);
}

export class TtsVoiceCatalog {
  private static readonly ENTRIES: TtsVoiceCatalogEntry[] = buildEntries();

  static allEntries(): TtsVoiceCatalogEntry[] {
    return TtsVoiceCatalog.ENTRIES;
  }

  /** 已在应用内实现朗读的语种（不含 Piper 扩展 3 种） */
  static coreEntries(): TtsVoiceCatalogEntry[] {
    const out: TtsVoiceCatalogEntry[] = [];
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      if (!TtsVoiceCatalog.isPiperExtensionEntry(TtsVoiceCatalog.ENTRIES[i])) {
        out.push(TtsVoiceCatalog.ENTRIES[i]);
      }
    }
    return out;
  }

  /** Piper 官方语音库中、尚未并入「已支持」的 3 种 */
  static piperExtensionEntries(): TtsVoiceCatalogEntry[] {
    const out: TtsVoiceCatalogEntry[] = [];
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      if (TtsVoiceCatalog.isPiperExtensionEntry(TtsVoiceCatalog.ENTRIES[i])) {
        out.push(TtsVoiceCatalog.ENTRIES[i]);
      }
    }
    return out;
  }

  private static isPiperExtensionEntry(entry: TtsVoiceCatalogEntry): boolean {
    return entry.engine === 'piper' && entry.iso !== 'ja' &&
      TtsPiperVoiceCatalog.findByIso(entry.iso) !== undefined;
  }

  /**
   * FLORES/NLLB 语言表 isoCode（如 kat）与 TTS 目录 iso（如 ka）不一致时，统一为朗读用 iso。
   */
  static normalizeSpeakIso(iso: string): string {
    const code = iso.trim().toLowerCase();
    if (code === 'kat') {
      return 'ka';
    }
    if (code === 'kir') {
      return 'ky';
    }
    if (code === 'por') {
      return 'pt';
    }
    if (code === 'pol') {
      return 'pl';
    }
    if (code === 'spa') {
      return 'es';
    }
    if (code === 'mkd') {
      return 'mk';
    }
    if (code === 'als' || code === 'sqi') {
      return 'sq';
    }
    if (code === 'epo') {
      return 'eo';
    }
    if (code === 'deu') {
      return 'de';
    }
    if (code === 'fra') {
      return 'fr';
    }
    if (code === 'ita') {
      return 'it';
    }
    if (code === 'tur') {
      return 'tr';
    }
    if (code === 'vie') {
      return 'vi';
    }
    if (code === 'nld') {
      return 'nl';
    }
    if (code === 'hin') {
      return 'hi';
    }
    if (code === 'cat') {
      return 'ca';
    }
    if (code === 'ces') {
      return 'cs';
    }
    if (code === 'cym') {
      return 'cy';
    }
    if (code === 'dan') {
      return 'da';
    }
    if (code === 'ell') {
      return 'el';
    }
    if (code === 'pes') {
      return 'fa';
    }
    if (code === 'fin') {
      return 'fi';
    }
    if (code === 'hun') {
      return 'hu';
    }
    if (code === 'isl') {
      return 'is';
    }
    if (code === 'kaz') {
      return 'kk';
    }
    if (code === 'ltz') {
      return 'lb';
    }
    if (code === 'lvs') {
      return 'lv';
    }
    if (code === 'mal') {
      return 'ml';
    }
    if (code === 'npi') {
      return 'ne';
    }
    if (code === 'nob') {
      return 'no';
    }
    if (code === 'ron') {
      return 'ro';
    }
    if (code === 'slk') {
      return 'sk';
    }
    if (code === 'slv') {
      return 'sl';
    }
    if (code === 'srp') {
      return 'sr';
    }
    if (code === 'swe') {
      return 'sv';
    }
    if (code === 'swh') {
      return 'sw';
    }
    return code;
  }

  static supportedIsos(): string[] {
    const out: string[] = [];
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      out.push(TtsVoiceCatalog.ENTRIES[i].iso);
    }
    return out;
  }

  static rhvoiceIsos(): string[] {
    const out: string[] = [];
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      if (TtsVoiceCatalog.ENTRIES[i].engine === 'rhvoice') {
        out.push(TtsVoiceCatalog.ENTRIES[i].iso);
      }
    }
    return out;
  }

  static piperIsos(): string[] {
    const out: string[] = [];
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      if (TtsVoiceCatalog.ENTRIES[i].engine === 'piper') {
        out.push(TtsVoiceCatalog.ENTRIES[i].iso);
      }
    }
    return out;
  }

  static findByIso(iso: string): TtsVoiceCatalogEntry | undefined {
    const code = TtsVoiceCatalog.normalizeSpeakIso(iso);
    for (let i = 0; i < TtsVoiceCatalog.ENTRIES.length; i++) {
      if (TtsVoiceCatalog.ENTRIES[i].iso === code) {
        return TtsVoiceCatalog.ENTRIES[i];
      }
    }
    return undefined;
  }

  static labelForIso(iso: string): string {
    const hit = TtsVoiceCatalog.findByIso(iso);
    if (hit !== undefined) {
      return hit.label;
    }
    return iso.toUpperCase();
  }

  static rhvoiceProfileForIso(iso: string): string {
    const hit = TtsVoiceCatalog.findByIso(iso);
    return hit?.rhvoiceProfile ?? '';
  }

  static piperVoiceKeyForIso(iso: string): string {
    const hit = TtsVoiceCatalog.findByIso(iso);
    if (hit?.piperVoiceKey !== undefined && hit.piperVoiceKey.length > 0) {
      return hit.piperVoiceKey;
    }
    return TtsPiperVoiceCatalog.voiceKeyForIso(iso);
  }
}
