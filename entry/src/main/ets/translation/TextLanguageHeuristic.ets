import { TextDecorationUtil } from './TextDecorationUtil';

/** 与 Android TextLanguageHeuristic 对齐的粗略语种推断 */
export class TextLanguageHeuristic {
  static guessIsoCode(text: string): string {
    const body = TextDecorationUtil.stripForLanguageDetection(text).trim();
    if (body.length === 0) {
      return 'en';
    }
    let cjk = 0;
    let arabic = 0;
    let cyrillic = 0;
    const len = body.length;
    for (let i = 0; i < len; i++) {
      const ch = body.charCodeAt(i);
      if ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3040 && ch <= 0x30FF) || (ch >= 0xAC00 && ch <= 0xD7AF)) {
        cjk++;
      } else if (ch >= 0x0600 && ch <= 0x06FF) {
        arabic++;
      } else if (ch >= 0x0400 && ch <= 0x04FF) {
        cyrillic++;
      }
    }
    const lower = body.toLowerCase();
    if (len <= 64 && TextLanguageHeuristic.looksPortugueseHint(lower)) {
      return 'por';
    }
    if (len <= 64 && TextLanguageHeuristic.looksAlbanianHint(lower)) {
      return 'als';
    }
    if (len <= 64 && TextLanguageHeuristic.looksEsperantoHint(lower)) {
      return 'epo';
    }
    if (len <= 48 && TextLanguageHeuristic.looksSpanishHint(lower)) {
      return 'es';
    }
    if (cjk * 3 >= len) {
      return 'zh';
    }
    if (arabic * 3 >= len) {
      return 'ar';
    }
    if (cyrillic * 3 >= len) {
      if (TextLanguageHeuristic.looksMacedonianCyrillic(body)) {
        return 'mkd';
      }
      if (TextLanguageHeuristic.looksTatarCyrillic(body)) {
        return 'tat';
      }
      if (TextLanguageHeuristic.looksKyrgyzCyrillic(body)) {
        return 'kir';
      }
      return 'ru';
    }
    return 'en';
  }

  /** 马其顿语西里尔：ќ、ѓ、љ、њ、џ 等 */
  private static looksMacedonianCyrillic(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if (ch === 0x0453 || ch === 0x0459 || ch === 0x045A || ch === 0x045C || ch === 0x045F) {
        return true;
      }
    }
    return false;
  }

  /** 鞑靼语西里尔：җ、ә 等（RHVoice Tatar） */
  private static looksTatarCyrillic(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if (ch === 0x04D7 || ch === 0x04D8 || ch === 0x04D9) {
        return true;
      }
    }
    return false;
  }

  /** 吉尔吉斯语西里尔字母：ө ү ң 等（与俄语区分） */
  private static looksKyrgyzCyrillic(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      const ch = text.charCodeAt(i);
      if (ch === 0x04E8 || ch === 0x04E9 || ch === 0x04AE || ch === 0x04AF ||
        ch === 0x04A2 || ch === 0x04A3) {
        return true;
      }
    }
    return false;
  }

  private static looksEsperantoHint(lower: string): boolean {
    for (let i = 0; i < lower.length; i++) {
      const ch = lower.charCodeAt(i);
      if (ch === 0x0109 || ch === 0x011D || ch === 0x0125 || ch === 0x0135 ||
        ch === 0x015D || ch === 0x016D) {
        return true;
      }
    }
    const tokens = [
      'saluton', 'dankon', 'esperanto', 'kaj ', ' estas', 'por ', ' ne ',
      'jes', 'bonan', 'ĝis', 'gis ', 'cx ', 'gx ', 'sx ', 'ux ',
    ];
    for (let i = 0; i < tokens.length; i++) {
      if (lower.indexOf(tokens[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static looksAlbanianHint(lower: string): boolean {
    if (lower.indexOf('ë') >= 0 || lower.indexOf('ç') >= 0) {
      return true;
    }
    const tokens = [
      'dhe ', 'është', 'eshte', 'për ', 'per ', 'nuk ', 'një', 'nje ',
      'mirë', 'mire', 'faleminderit', 'shqip', 'ju lutem',
    ];
    for (let i = 0; i < tokens.length; i++) {
      if (lower.indexOf(tokens[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static looksPortugueseHint(lower: string): boolean {
    if (lower.indexOf('ã') >= 0 || lower.indexOf('õ') >= 0 || lower.indexOf('ç') >= 0) {
      return true;
    }
    const tokens = [
      'não', 'nao', 'você', 'voce', 'obrigado', 'obrigada', 'português', 'portugues',
      'bom dia', 'boa tarde', 'boa noite', 'tchau', 'por favor', 'desculpe',
      'está', 'esta ', 'são', 'sao ', 'uma ', 'um ', 'como ', 'muito',
    ];
    for (let i = 0; i < tokens.length; i++) {
      if (lower.indexOf(tokens[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static looksSpanishHint(lower: string): boolean {
    if (lower.indexOf('ñ') >= 0 || lower.indexOf('¿') >= 0 || lower.indexOf('¡') >= 0) {
      return true;
    }
    const tokens = [
      'hola', 'gracias', 'adiós', 'adios', 'por favor', 'buenos días', 'buenas',
      'qué', 'que ', ' cómo ', 'como ', 'bien', 'mucho', 'señor', 'señora',
    ];
    for (let i = 0; i < tokens.length; i++) {
      if (lower.indexOf(tokens[i]) >= 0) {
        return true;
      }
    }
    return false;
  }
}
