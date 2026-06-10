import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ct2native, { NativeTranslateResult } from 'libctranslate2_napi.so';
import { NllbModelPaths } from './NllbModelPaths';
import { TranslateLanguages } from './TranslateLanguages';

const DOMAIN = 0x4E4C4C; // NLLB
/** 单段送入 NLLB 的最大字符数，超长文本分段翻译以避免重复与截断 */
const MAX_CHUNK_CHARS = 280;

/**
 * 本机 CTranslate2 + NLLB-200（与仓库 CTranslate2/ 源码对齐）。
 * 未链接 CT2、未放置模型或推理失败时返回 null。
 */
export class CTranslate2Engine {
  private static filesDir: string = '';
  private static resourceDir: string = '';
  private static modelDir: string = '';
  private static initialized: boolean = false;
  private static modelPresent: boolean = false;
  private static ct2Linked: boolean = false;
  private static engineLoaded: boolean = false;
  private static warmedUp: boolean = false;
  private static lastError: string = '';
  private static loadPromise: Promise<void> | null = null;

  static init(context: common.Context): void {
    CTranslate2Engine.filesDir = context.filesDir;
    CTranslate2Engine.resourceDir = context.resourceDir ?? '';
    CTranslate2Engine.engineLoaded = false;
    CTranslate2Engine.lastError = '';
    try {
      CTranslate2Engine.ct2Linked = ct2native.isCt2Linked();
      const filesDirModel = NllbModelPaths.modelRoot(CTranslate2Engine.filesDir);
      const dirs: string[] = [filesDirModel];
      const bundledCandidates = NllbModelPaths.bundledModelDirCandidates(CTranslate2Engine.resourceDir);
      for (let i = 0; i < bundledCandidates.length; i++) {
        dirs.push(bundledCandidates[i]);
      }
      CTranslate2Engine.modelDir = filesDirModel;
      CTranslate2Engine.modelPresent = false;
      for (let j = 0; j < dirs.length; j++) {
        const candidate = dirs[j];
        if (candidate.length > 0 && ct2native.isModelPresent(candidate)) {
          CTranslate2Engine.modelDir = candidate;
          CTranslate2Engine.modelPresent = true;
          break;
        }
      }
      CTranslate2Engine.initialized = true;
      CTranslate2Engine.warmedUp = false;
      hilog.info(DOMAIN, 'CT2',
        'init linked=%{public}s model=%{public}s dir=%{public}s info=%{public}s',
        String(CTranslate2Engine.ct2Linked),
        String(CTranslate2Engine.modelPresent),
        CTranslate2Engine.modelDir,
        ct2native.getBuildInfo());
      hilog.info(0x0000, 'testTag',
        'CT2 init linked=%{public}s model=%{public}s dir=%{public}s',
        String(CTranslate2Engine.ct2Linked),
        String(CTranslate2Engine.modelPresent),
        CTranslate2Engine.modelDir);
    } catch (e) {
      CTranslate2Engine.initialized = false;
      hilog.error(DOMAIN, 'CT2', 'native init failed: %{public}s', JSON.stringify(e));
    }
  }

  static isInitialized(): boolean {
    return CTranslate2Engine.initialized;
  }

  static isCt2LibraryLinked(): boolean {
    return CTranslate2Engine.ct2Linked;
  }

  static isEngineLoaded(): boolean {
    return CTranslate2Engine.engineLoaded;
  }

  static getLastError(): string {
    return CTranslate2Engine.lastError;
  }

  static getBuildInfo(): string {
    try {
      return ct2native.getBuildInfo();
    } catch (_e) {
      return '';
    }
  }

  static isModelInstalled(): boolean {
    return CTranslate2Engine.modelPresent;
  }

  static getModelDir(): string {
    return CTranslate2Engine.modelDir;
  }

  /** 将 NLLB 模型载入内存（native 线程池异步，首译前必须成功） */
  static async loadModelIntoMemory(): Promise<boolean> {
    CTranslate2Engine.lastError = '';
    if (!CTranslate2Engine.isReadyForOffline()) {
      CTranslate2Engine.lastError = 'model or CT2 not ready';
      return false;
    }
    try {
      const load = await ct2native.loadModel(CTranslate2Engine.modelDir);
      if (load.ok) {
        CTranslate2Engine.engineLoaded = true;
        hilog.info(DOMAIN, 'CT2', 'loadModel ok dir=%{public}s', CTranslate2Engine.modelDir);
        hilog.info(0x0000, 'testTag', 'CT2 loadModel ok');
        return true;
      }
      CTranslate2Engine.engineLoaded = false;
      CTranslate2Engine.lastError = load.error.length > 0 ? load.error : 'loadModel failed';
      hilog.error(DOMAIN, 'CT2', 'loadModel failed: %{public}s', CTranslate2Engine.lastError);
      hilog.error(0x0000, 'testTag', 'CT2 loadModel failed: %{public}s', CTranslate2Engine.lastError);
      return false;
    } catch (e) {
      CTranslate2Engine.engineLoaded = false;
      CTranslate2Engine.lastError = JSON.stringify(e);
      hilog.error(DOMAIN, 'CT2', 'loadModel exception: %{public}s', CTranslate2Engine.lastError);
      return false;
    }
  }

  static async ensureEngineLoaded(): Promise<void> {
    if (CTranslate2Engine.engineLoaded) {
      return;
    }
    if (!CTranslate2Engine.isReadyForOffline()) {
      throw new Error('MODEL_NOT_READY: 本机模型文件未就绪');
    }
    if (CTranslate2Engine.loadPromise !== null) {
      await CTranslate2Engine.loadPromise;
      if (!CTranslate2Engine.engineLoaded) {
        const detail = CTranslate2Engine.lastError;
        throw new Error(`MODEL_NOT_READY: 本机翻译引擎加载失败: ${detail}`);
      }
      return;
    }
    CTranslate2Engine.loadPromise = (async (): Promise<void> => {
      const ok = await CTranslate2Engine.loadModelIntoMemory();
      if (!ok) {
        const detail = CTranslate2Engine.lastError;
        throw new Error(`MODEL_NOT_READY: 本机翻译引擎加载失败: ${detail}`);
      }
    })();
    try {
      await CTranslate2Engine.loadPromise;
    } finally {
      CTranslate2Engine.loadPromise = null;
    }
  }

  /** 安装完成后延迟预加载，避免在 onCreate 主线程同步 loadModel 触发 LIFECYCLE_HALF_TIMEOUT */
  static preloadInBackground(): void {
    if (!CTranslate2Engine.isReadyForOffline() || CTranslate2Engine.engineLoaded) {
      return;
    }
    setTimeout(() => {
      void CTranslate2Engine.ensureEngineLoaded().then(() => {
        void CTranslate2Engine.warmUp();
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, 'CT2', 'preload failed: %{public}s', e.message ?? '');
        hilog.warn(0x0000, 'testTag', 'CT2 preload failed: %{public}s', e.message ?? '');
      });
    }, 500);
  }

  static async warmUp(): Promise<void> {
    if (CTranslate2Engine.warmedUp || !CTranslate2Engine.isReadyForOffline()) {
      return;
    }
    await CTranslate2Engine.ensureEngineLoaded();
    const out = await CTranslate2Engine.translate('你好', 'zh', 'en');
    if (out !== null && out.length > 0) {
      CTranslate2Engine.warmedUp = true;
      hilog.info(DOMAIN, 'CT2', 'warmup done out=%{public}s', out);
      hilog.info(0x0000, 'testTag', 'CT2 warmup ok');
    } else {
      hilog.warn(DOMAIN, 'CT2', 'warmup translate empty: %{public}s', CTranslate2Engine.lastError);
    }
  }

  /** 模型文件齐全且已链接 CT2（尚未保证已 loadModel） */
  static isReadyForOffline(): boolean {
    return CTranslate2Engine.initialized &&
      CTranslate2Engine.ct2Linked &&
      CTranslate2Engine.modelPresent;
  }

  /** 可立即推理：文件就绪且已成功 loadModel */
  static canTranslateNow(): boolean {
    return CTranslate2Engine.isReadyForOffline() && CTranslate2Engine.engineLoaded;
  }

  static refreshModelPresence(): void {
    if (!CTranslate2Engine.initialized || CTranslate2Engine.modelDir.length === 0) {
      return;
    }
    try {
      if (ct2native.isModelPresent(CTranslate2Engine.modelDir)) {
        CTranslate2Engine.modelPresent = true;
        return;
      }
      const filesDirModel = NllbModelPaths.modelRoot(CTranslate2Engine.filesDir);
      const bundledCandidates = NllbModelPaths.bundledModelDirCandidates(CTranslate2Engine.resourceDir);
      for (let i = 0; i < bundledCandidates.length; i++) {
        const bundledDir = bundledCandidates[i];
        if (bundledDir.length > 0 && ct2native.isModelPresent(bundledDir)) {
          CTranslate2Engine.modelDir = bundledDir;
          CTranslate2Engine.modelPresent = true;
          return;
        }
      }
      CTranslate2Engine.modelDir = filesDirModel;
      CTranslate2Engine.modelPresent = ct2native.isModelPresent(CTranslate2Engine.modelDir);
    } catch (_e) {
      CTranslate2Engine.modelPresent = false;
    }
    if (!CTranslate2Engine.modelPresent) {
      CTranslate2Engine.engineLoaded = false;
    }
  }

  private static splitTranslationChunks(text: string): string[] {
    if (text.length <= MAX_CHUNK_CHARS) {
      return [text];
    }
    const paragraphs = text.split(/\n{2,}/);
    const chunks: string[] = [];
    let buf = '';
    const flushBuf = (): void => {
      if (buf.length > 0) {
        chunks.push(buf);
        buf = '';
      }
    };
    const pushSentences = (block: string): void => {
      const parts: string[] = [];
      let start = 0;
      for (let i = 0; i < block.length; i++) {
        const c = block.charAt(i);
        if ('。！？.!?\n'.indexOf(c) >= 0) {
          const seg = block.substring(start, i + 1).trim();
          if (seg.length > 0) {
            parts.push(seg);
          }
          start = i + 1;
        }
      }
      const tail = block.substring(start).trim();
      if (tail.length > 0) {
        parts.push(tail);
      }
      for (let i = 0; i < parts.length; i++) {
        const part = parts[i].trim();
        if (part.length === 0) {
          continue;
        }
        if (part.length > MAX_CHUNK_CHARS) {
          flushBuf();
          for (let j = 0; j < part.length; j += MAX_CHUNK_CHARS) {
            chunks.push(part.substring(j, j + MAX_CHUNK_CHARS));
          }
          continue;
        }
        if (buf.length === 0) {
          buf = part;
        } else if (buf.length + 1 + part.length <= MAX_CHUNK_CHARS) {
          buf = `${buf} ${part}`;
        } else {
          flushBuf();
          buf = part;
        }
      }
      flushBuf();
    };
    for (let p = 0; p < paragraphs.length; p++) {
      const para = paragraphs[p].trim();
      if (para.length === 0) {
        continue;
      }
      if (para.length <= MAX_CHUNK_CHARS) {
        if (buf.length === 0) {
          buf = para;
        } else if (buf.length + 2 + para.length <= MAX_CHUNK_CHARS) {
          buf = `${buf}\n\n${para}`;
        } else {
          flushBuf();
          buf = para;
        }
      } else {
        flushBuf();
        pushSentences(para);
      }
    }
    flushBuf();
    return chunks.length > 0 ? chunks : [text];
  }

  private static async translateChunk(
    body: string,
    sourceNllb: string,
    targetNllb: string
  ): Promise<string | null> {
    const result: NativeTranslateResult =
      await ct2native.translate(body, sourceNllb, targetNllb, CTranslate2Engine.modelDir);
    const out: string = result.text.trim();
    const err: string = result.error.trim();
    if (out.length > 0) {
      return out;
    }
    CTranslate2Engine.lastError = err.length > 0 ? err : 'empty translation';
    return null;
  }

  /**
   * @returns 译文；不可用或失败时返回 null，详情见 getLastError()
   * 推理在 native 线程池执行，避免主线程同步 NAPI 触发 ANR。
   */
  static async translate(text: string, sourceIso: string, targetIso: string): Promise<string | null> {
    CTranslate2Engine.lastError = '';
    if (!CTranslate2Engine.isReadyForOffline()) {
      CTranslate2Engine.lastError = 'not ready for offline';
      return null;
    }
    if (!CTranslate2Engine.engineLoaded) {
      CTranslate2Engine.lastError = 'engine not loaded';
      return null;
    }
    const body = text.trim();
    if (body.length === 0) {
      return null;
    }
    const sourceNllb = TranslateLanguages.nllbForIsoCode(sourceIso);
    const targetNllb = TranslateLanguages.nllbForIsoCode(targetIso);
    if (sourceNllb === targetNllb) {
      return body;
    }
    try {
      const chunks = CTranslate2Engine.splitTranslationChunks(body);
      const outs: string[] = [];
      for (let i = 0; i < chunks.length; i++) {
        const piece = await CTranslate2Engine.translateChunk(chunks[i], sourceNllb, targetNllb);
        if (piece === null) {
          hilog.error(DOMAIN, 'CT2', 'translate failed %{public}s->%{public}s chunk %{public}d: %{public}s',
            sourceIso, targetIso, i, CTranslate2Engine.lastError);
          hilog.error(0x0000, 'testTag', 'CT2 translate failed: %{public}s', CTranslate2Engine.lastError);
          return null;
        }
        outs.push(piece);
      }
      const joiner = body.includes('\n\n') ? '\n\n' : ' ';
      return outs.join(chunks.length > 1 ? joiner : '');
    } catch (e) {
      CTranslate2Engine.lastError = JSON.stringify(e);
      hilog.error(DOMAIN, 'CT2', 'translate exception: %{public}s', CTranslate2Engine.lastError);
    }
    return null;
  }
}
