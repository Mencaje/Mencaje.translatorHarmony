import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SileroInstallFailure, SileroModelInstaller } from './SileroModelInstaller';
import { SileroModelPaths } from './SileroModelPaths';
import { SileroTtsNative } from './SileroTtsNative';

/** 列表行状态：已安装 / 待安装 / 安装中 */
export enum TtsVoiceRowState {
  READY = 0,
  NEED_DOWNLOAD = 1,
  DOWNLOADING = 2,
  UNAVAILABLE = 3,
  /** 语音包已在本地，但本机推理库未编入 HAP（真机未跑 prepare_native_tts） */
  NEED_ENGINE = 4,
  /** 本机 HAP 切片未编入对应推理库（缺 libpiper_plus 等） */
  NEED_REAL_DEVICE = 5,
}

export interface TtsVoiceRowStatus {
  iso: string;
  state: TtsVoiceRowState;
  progress: number;
}

/**
 * Silero 语音包状态（本机 C++ + rawfile 模型，不使用系统 TTS、不联网下载）。
 */
export class TtsVoiceManager {
  private static appContext: common.Context | undefined = undefined;
  private static capabilityOk: boolean = false;
  private static downloadingIso: string = '';
  private static downloadProgress: number = 0;

  static init(context: common.Context): void {
    // 保留 UIAbility 上下文：ApplicationContext 上 resourceDir/rawfd 常不可用（日语 resfile zip）
    TtsVoiceManager.appContext = context;
    SileroTtsNative.init(context);
    TtsVoiceManager.capabilityOk = SileroTtsNative.isInitialized();
  }

  static isCapabilityOk(): boolean {
    return TtsVoiceManager.capabilityOk;
  }

  static getFilesDir(): string {
    const ctx = TtsVoiceManager.appContext;
    return ctx !== undefined ? ctx.filesDir : '';
  }

  static getDownloadProgress(): number {
    return TtsVoiceManager.downloadProgress;
  }

  static getDownloadingIso(): string {
    return TtsVoiceManager.downloadingIso;
  }

  static isDownloading(): boolean {
    return TtsVoiceManager.downloadingIso.length > 0;
  }

  static invalidate(_iso?: string): void {
  }

  /** 朗读语种：zh=SummerTTS，ja + Piper 语种=piper-plus */
  static isOfferedState(state: TtsVoiceRowState): boolean {
    return state !== TtsVoiceRowState.UNAVAILABLE;
  }

  static isOfferedIso(iso: string): boolean {
    return SileroModelPaths.isSupportedIso(iso);
  }

  /** 当前语种对应的 native 推理后端是否已编入本机 HAP 切片 */
  static isNativeEngineReadyForIso(iso: string): boolean {
    return SileroTtsNative.backendReadyForIso(iso);
  }

  static async queryRowStatus(iso: string): Promise<TtsVoiceRowStatus> {
    const code = iso.trim().toLowerCase();
    if (!SileroModelPaths.isSupportedIso(code)) {
      return { iso: code, state: TtsVoiceRowState.UNAVAILABLE, progress: 0 };
    }
    if (!TtsVoiceManager.capabilityOk) {
      return { iso: code, state: TtsVoiceRowState.UNAVAILABLE, progress: 0 };
    }
    if (TtsVoiceManager.downloadingIso === code) {
      return {
        iso: code,
        state: TtsVoiceRowState.DOWNLOADING,
        progress: TtsVoiceManager.downloadProgress,
      };
    }
    const ctx = TtsVoiceManager.appContext;
    if (ctx !== undefined && SileroModelInstaller.hasVoiceAssets(code, ctx.filesDir)) {
      SileroTtsNative.refreshLinkState();
      const inferOk = SileroModelInstaller.hasMobileInferenceModel(code, ctx.filesDir);
      if (!inferOk) {
        return { iso: code, state: TtsVoiceRowState.NEED_DOWNLOAD, progress: 0 };
      }
      if (SileroTtsNative.backendReadyForIso(code)) {
        return { iso: code, state: TtsVoiceRowState.READY, progress: 0 };
      }
      if (!SileroTtsNative.isSileroLibraryLinked()) {
        return { iso: code, state: TtsVoiceRowState.NEED_ENGINE, progress: 0 };
      }
      if (code === 'ja' && SileroTtsNative.isJaPiperUnavailableOnThisSlice()) {
        return { iso: code, state: TtsVoiceRowState.NEED_REAL_DEVICE, progress: 0 };
      }
      return { iso: code, state: TtsVoiceRowState.NEED_ENGINE, progress: 0 };
    }
    return { iso: code, state: TtsVoiceRowState.NEED_DOWNLOAD, progress: 0 };
  }

  static async isVoiceReady(iso: string): Promise<boolean> {
    const row = await TtsVoiceManager.queryRowStatus(iso);
    return row.state === TtsVoiceRowState.READY;
  }

  static async ensureDownloaded(iso: string): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    await SileroModelInstaller.waitForInstallIdle();
    if (await TtsVoiceManager.isVoiceReady(code)) {
      return true;
    }
    return await TtsVoiceManager.downloadVoiceForIso(code);
  }

  static getLastInstallFailure(): SileroInstallFailure {
    return SileroModelInstaller.getLastFailure();
  }

  static getLastInstallFailureDetail(): string {
    return SileroModelInstaller.getLastFailureDetail();
  }

  static async isRawBundledForIso(iso: string): Promise<boolean> {
    const ctx = TtsVoiceManager.appContext;
    if (ctx === undefined) {
      return false;
    }
    return await SileroModelInstaller.isRawBundledForIso(ctx, iso);
  }

  static async downloadVoiceForIso(iso: string): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    const ctx = TtsVoiceManager.appContext;
    if (!TtsVoiceManager.capabilityOk || ctx === undefined) {
      return false;
    }
    if (TtsVoiceManager.downloadingIso.length > 0 && TtsVoiceManager.downloadingIso !== code) {
      return false;
    }
    if (TtsVoiceManager.downloadingIso === code) {
      return await TtsVoiceManager.isVoiceReady(code);
    }
    if (await TtsVoiceManager.isVoiceReady(code)) {
      return true;
    }
    TtsVoiceManager.downloadingIso = code;
    TtsVoiceManager.downloadProgress = 0;
    const ok = await new Promise<boolean>((resolve) => {
      SileroModelInstaller.installLangIfNeeded(ctx, code,
        (p: number) => {
          TtsVoiceManager.downloadProgress = p;
        },
        (done: boolean) => {
          resolve(done);
        });
    });
    TtsVoiceManager.downloadingIso = '';
    TtsVoiceManager.downloadProgress = 0;
    if (!ok) {
      return false;
    }
    if (SileroModelInstaller.hasVoiceAssets(code, ctx.filesDir)) {
      return true;
    }
    if (code === 'ja') {
      hilog.error(0x0000, 'testTag',
        'piper ja install callback ok but hasVoiceAssets=false — forcing reinstall path');
      SileroModelInstaller.clearPiperJaVoiceCache(ctx.filesDir);
      SileroModelInstaller.recordInstallIncomplete('ja',
        '语音文件未通过校验（可能为不完整解压），已清除缓存请重试');
    }
    return false;
  }
}
