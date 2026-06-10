import { CTranslate2Engine } from './CTranslate2Engine';
import { NllbModelInstaller } from './NllbModelInstaller';
import { TextDecorationUtil } from './TextDecorationUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TRANSLATE_DOMAIN = 0x4E4C4C;

/**
 * 翻译入口：默认仅本机 NLLB（完整包：从 resourceDir/resfile 原地加载；小包：导入到 filesDir）。
 * 仅使用本机离线翻译；不依赖网络兜底。
 */
export class OnDeviceTranslator {
  static readonly MODEL_NOT_READY: string = 'MODEL_NOT_READY';

  /** 本机 NLLB 是否可离线翻译（CT2 已链接且模型已放入 filesDir） */
  static isModelReady(): boolean {
    return CTranslate2Engine.canTranslateNow();
  }

  static async translate(text: string, sourceIso: string, targetIso: string): Promise<string> {
    const body = text.trim();
    if (body.length === 0) {
      throw new Error('empty text');
    }
    if (sourceIso === targetIso) {
      return body;
    }
    if (TextDecorationUtil.isDecorationOnly(body)) {
      return body;
    }
    const mapped = OnDeviceTranslator.lookupPhrase(body, sourceIso, targetIso);
    if (mapped !== null) {
      return mapped;
    }
    await OnDeviceTranslator.ensureLocalModelReady();
    await CTranslate2Engine.ensureEngineLoaded();

    return await TextDecorationUtil.mergeTranslated(text, async (part: string): Promise<string> => {
      const out = await CTranslate2Engine.translate(part, sourceIso, targetIso);
      if (out !== null) {
        return out;
      }
      if (!CTranslate2Engine.isCt2LibraryLinked()) {
        throw new Error(OnDeviceTranslator.MODEL_NOT_READY +
          ': 未链接本机翻译库，请重新编译安装应用');
      }
      if (!CTranslate2Engine.isReadyForOffline()) {
        throw new Error(OnDeviceTranslator.MODEL_NOT_READY +
          ': 本机模型未就绪。请在「设置 → 离线翻译模型」安装/导入模型');
      }
      const detail = CTranslate2Engine.getLastError();
      hilog.error(TRANSLATE_DOMAIN, 'CT2',
        'local inference failed %{public}s -> %{public}s: %{public}s', sourceIso, targetIso, detail);
      throw new Error(OnDeviceTranslator.MODEL_NOT_READY +
        `: 本机翻译引擎推理失败: ${detail.length > 0 ? detail : '请重启应用后重试'}`);
    });
  }

  /** 等待首启从 HAP 解压 NLLB（由 EntryAbility 触发） */
  private static async ensureLocalModelReady(): Promise<void> {
    if (CTranslate2Engine.canTranslateNow()) {
      return;
    }
    if (CTranslate2Engine.isReadyForOffline()) {
      await CTranslate2Engine.ensureEngineLoaded();
      return;
    }
    const done = await NllbModelInstaller.whenInstallDone();
    CTranslate2Engine.refreshModelPresence();
    if (CTranslate2Engine.isReadyForOffline()) {
      await CTranslate2Engine.ensureEngineLoaded();
      return;
    }
    if (!CTranslate2Engine.isCt2LibraryLinked()) {
      throw new Error(OnDeviceTranslator.MODEL_NOT_READY +
        ': 未链接本机翻译库，请 DevEco「Clean Project」后重新编译安装到真机（非旧 HAP）');
    }
    if (!done) {
      throw new Error(OnDeviceTranslator.MODEL_NOT_READY +
        ': 本机 NLLB 未打包进当前安装包。请用含模型的完整 HAP 重装，或在设置中导入模型');
    }
    CTranslate2Engine.refreshModelPresence();
    if (CTranslate2Engine.isReadyForOffline()) {
      await CTranslate2Engine.ensureEngineLoaded();
      return;
    }
    throw new Error(OnDeviceTranslator.MODEL_NOT_READY + ': 正在加载本机翻译模型，请稍候再试');
  }

  /** 兼容旧同步调用名；内部走异步需由调用方 await translate */
  static translateBlocking(text: string, sourceIso: string, targetIso: string): string {
    throw new Error('请使用 OnDeviceTranslator.translate() 异步方法');
  }

  static async translateLines(lines: string[], sourceIso: string, targetIso: string): Promise<string[]> {
    const outs: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.trim().length === 0) {
        outs.push('');
      } else {
        outs.push(await OnDeviceTranslator.translate(line, sourceIso, targetIso));
      }
    }
    return outs;
  }

  static async translatePreservingNewlines(text: string, sourceIso: string, targetIso: string): Promise<string> {
    const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    if (normalized.trim().length === 0) {
      throw new Error('empty text');
    }
    if (sourceIso === targetIso) {
      return normalized;
    }
    return await OnDeviceTranslator.translate(normalized, sourceIso, targetIso);
  }

  private static normalizePhraseKey(text: string): string {
    return text.trim().replace(/\s+/g, ' ');
  }

  private static lookupPhrase(text: string, sourceIso: string, targetIso: string): string | null {
    const key = `${sourceIso}|${targetIso}|${OnDeviceTranslator.normalizePhraseKey(text)}`;
    const table: string[] = [
      'zh|en|你好', 'Hello',
      'zh|en|您好', 'Hello',
      'zh|uk|你好', 'Привіт',
      'zh|uk|您好', 'Вітаю',
    ];
    for (let i = 0; i < table.length; i += 2) {
      if (table[i] === key) {
        return table[i + 1];
      }
    }
    return null;
  }
}
