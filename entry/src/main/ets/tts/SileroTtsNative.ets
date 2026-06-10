import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import sileroNative, { NativeSynthesizeResult } from 'libsilero_tts_napi.so';
import { SileroModelPaths } from './SileroModelPaths';

export type { NativeSynthesizeResult };

const DOMAIN = 0x53494C; // SIL

const BUILD_MARKER_SUMMERTTS = '[summertts]';
const BUILD_MARKER_PIPERPLUS = '[piperplus]';
const BUILD_MARKER_STUB_X86 = '[stub-x86_64]';
const BUILD_MARKER_NO_INFERENCE = 'NO inference';

/**
 * Silero C++ NAPI 封装（禁止走系统 TTS）。
 */
export class SileroTtsNative {
  private static filesDir: string = '';
  private static modelRoot: string = '';
  private static initialized: boolean = false;
  private static sileroLinked: boolean = false;
  /** 串行化 native synthesize，避免 FFRT 上多个异步合成任务重叠。 */
  private static synthTail: Promise<void> = Promise.resolve();
  /** cancel 时递增，丢弃排队中的 synthesize 结果。 */
  private static synthEpoch: number = 0;

  /** 与 SileroModelInstaller / TtsVoiceManager 使用同一 filesDir（通常为 UIAbility 的 haps/entry/files）。 */
  static syncModelRoot(filesDir: string): void {
    const dir = filesDir.trim();
    if (dir.length === 0) {
      return;
    }
    SileroTtsNative.filesDir = dir;
    SileroTtsNative.modelRoot = SileroModelPaths.modelRoot(dir);
  }

  static init(context: common.Context): void {
    SileroTtsNative.syncModelRoot(context.filesDir);
    SileroTtsNative.initialized = true;
    try {
      SileroTtsNative.refreshLinkState();
      hilog.info(DOMAIN, 'Silero',
        'native init linked=%{public}s zh=%{public}s ja=%{public}s root=%{public}s info=%{public}s',
        String(SileroTtsNative.sileroLinked),
        String(SileroTtsNative.usesSummerTts()),
        String(SileroTtsNative.usesPiperPlus()),
        SileroTtsNative.modelRoot,
        SileroTtsNative.getBuildInfoCached());
    } catch (e) {
      SileroTtsNative.sileroLinked = false;
      hilog.error(DOMAIN, 'Silero', 'native probe failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 朗读前刷新：避免热更新未替换旧 .so 时仍用启动时的缓存 */
  static refreshLinkState(): void {
    const info = SileroTtsNative.getBuildInfoCached();
    let linked = false;
    try {
      linked = sileroNative.isSileroLinked();
    } catch (_e) {
      linked = false;
    }
    if (!linked && info.length > 0) {
      linked = SileroTtsNative.isEngineCompiledInBuildInfo(info);
    }
    SileroTtsNative.sileroLinked = linked;
  }

  /** 仅当 native 以 Sherpa/PyTorch 编入时为 true（勿用错误字符串里的 “Sherpa-ONNX” 判断） */
  static isEngineCompiledInBuildInfo(info: string): boolean {
    if (info.indexOf(BUILD_MARKER_NO_INFERENCE) >= 0) {
      return false;
    }
    return info.indexOf(BUILD_MARKER_SUMMERTTS) >= 0 ||
      info.indexOf(BUILD_MARKER_PIPERPLUS) >= 0;
  }

  private static buildInfoCache: string = '';

  static getBuildInfo(): string {
    return SileroTtsNative.getBuildInfoCached();
  }

  private static getBuildInfoCached(): string {
    try {
      SileroTtsNative.buildInfoCache = sileroNative.getBuildInfo();
    } catch (_e) {
      SileroTtsNative.buildInfoCache = '';
    }
    return SileroTtsNative.buildInfoCache;
  }

  static isInitialized(): boolean {
    return SileroTtsNative.initialized;
  }

  static isSileroLibraryLinked(): boolean {
    if (!SileroTtsNative.initialized) {
      return false;
    }
    SileroTtsNative.refreshLinkState();
    return SileroTtsNative.sileroLinked;
  }

  /** 当前进程加载的是 HAP 里 x86_64 切片（DevEco 常见 x86 模拟器） */
  static isX86HapSlice(): boolean {
    const info = SileroTtsNative.getBuildInfoCached();
    return info.indexOf('abi=x86_64') >= 0 || info.indexOf(BUILD_MARKER_STUB_X86) >= 0;
  }

  /** @deprecated 用 isX86HapSlice；x86 包现已可含 Sherpa+SummerTTS，仅日语 piper 缺省 */
  static isX86EmulatorStub(): boolean {
    return SileroTtsNative.isX86HapSlice();
  }

  /** 日语 piper-plus 未编入当前 ABI（仅 x86 切片且无 piper 时提示换真机） */
  static isJaPiperUnavailableOnThisSlice(): boolean {
    if (SileroTtsNative.usesPiperPlus()) {
      return false;
    }
    return SileroTtsNative.isX86HapSlice();
  }

  private static buildInfoHasFullTtsStack(info: string): boolean {
    return info.indexOf('[summertts+piperplus]') >= 0;
  }

  private static buildInfoDeniesInference(info: string): boolean {
    return info.indexOf(BUILD_MARKER_NO_INFERENCE) >= 0 ||
      info.indexOf('no native backend linked') >= 0;
  }

  /** 列表对勾 / speak：本机 HAP 是否已编入该语种推理后端 */
  static backendReadyForIso(iso: string): boolean {
    if (!SileroTtsNative.initialized) {
      return false;
    }
    const code = iso.trim().toLowerCase();
    const info = SileroTtsNative.getBuildInfoCached();
    if (SileroTtsNative.buildInfoDeniesInference(info)) {
      return false;
    }
    if (SileroTtsNative.buildInfoHasFullTtsStack(info)) {
      return SileroModelPaths.usesSummerTtsIso(code) ||
        SileroModelPaths.usesPiperIso(code);
    }
    if (SileroModelPaths.usesSummerTtsIso(code)) {
      return SileroTtsNative.usesSummerTts();
    }
    if (SileroModelPaths.usesPiperIso(code)) {
      return SileroTtsNative.usesPiperPlus();
    }
    return false;
  }

  /** RHVoice 已剔除（GPL-2.0），恒为 false */
  static usesRhvoice(): boolean {
    return false;
  }

  /** @deprecated 已移除 Sherpa */
  static usesSherpaOnnx(): boolean {
    return false;
  }

  /** 当前 HAP 编入 piper-plus（日语 ja） */
  static usesPiperPlus(): boolean {
    if (!SileroTtsNative.initialized) {
      return false;
    }
    const info = SileroTtsNative.getBuildInfoCached();
    if (SileroTtsNative.buildInfoDeniesInference(info)) {
      return false;
    }
    if (SileroTtsNative.buildInfoHasFullTtsStack(info)) {
      return true;
    }
    if (info.indexOf(BUILD_MARKER_PIPERPLUS) >= 0 || info.indexOf('piperplus') >= 0) {
      return true;
    }
    if (info.indexOf('[summertts+piperplus]') >= 0) {
      return true;
    }
    try {
      return sileroNative.usesPiperPlus();
    } catch (_e) {
      return false;
    }
  }

  /** 当前 HAP 编入 SummerTTS（中文 zh） */
  static usesSummerTts(): boolean {
    if (!SileroTtsNative.initialized) {
      return false;
    }
    const info = SileroTtsNative.getBuildInfoCached();
    if (SileroTtsNative.buildInfoDeniesInference(info)) {
      return false;
    }
    if (SileroTtsNative.buildInfoHasFullTtsStack(info)) {
      return true;
    }
    if (info.indexOf(BUILD_MARKER_SUMMERTTS) >= 0 || info.indexOf('summertts') >= 0) {
      return true;
    }
    if (info.indexOf('[summertts+piperplus]') >= 0) {
      return true;
    }
    if (info.indexOf('SummerTTS') >= 0 && info.indexOf('TTS NAPI') >= 0) {
      return true;
    }
    try {
      return sileroNative.usesSummerTts();
    } catch (_e) {
      return false;
    }
  }

  /** @deprecated 已移除 PyTorch/Silero */
  static usesPytorchMobile(): boolean {
    return false;
  }

  static getModelRoot(): string {
    return SileroTtsNative.modelRoot;
  }

  static isLangModelPresent(iso: string): boolean {
    if (!SileroTtsNative.initialized || SileroTtsNative.modelRoot.length === 0) {
      return false;
    }
    try {
      return sileroNative.isLangModelPresent(SileroTtsNative.modelRoot, iso.trim().toLowerCase());
    } catch (_e) {
      return false;
    }
  }

  static cancelSynthesis(): void {
    SileroTtsNative.synthEpoch++;
    SileroTtsNative.synthTail = Promise.resolve();
    if (!SileroTtsNative.initialized) {
      return;
    }
    try {
      sileroNative.cancelSynthesis();
    } catch (_e) {
    }
  }

  static async synthesize(text: string, langIso: string): Promise<NativeSynthesizeResult | undefined> {
    if (!SileroTtsNative.initialized) {
      return undefined;
    }
    const epoch = SileroTtsNative.synthEpoch;
    const previous = SileroTtsNative.synthTail;
    let release: () => void = () => {};
    SileroTtsNative.synthTail = new Promise<void>((resolve) => {
      release = resolve;
    });
    await previous;
    if (epoch !== SileroTtsNative.synthEpoch) {
      release();
      return undefined;
    }
    try {
      const result = await sileroNative.synthesize(langIso.trim().toLowerCase(), text, SileroTtsNative.modelRoot);
      if (epoch !== SileroTtsNative.synthEpoch) {
        return undefined;
      }
      return result;
    } catch (e) {
      hilog.error(DOMAIN, 'Silero', 'synthesize exception: %{public}s', JSON.stringify(e));
      return undefined;
    } finally {
      release();
    }
  }
}
