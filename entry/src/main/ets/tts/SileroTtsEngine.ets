import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SileroModelPaths } from './SileroModelPaths';
import { SileroPcmPlayer } from './SileroPcmPlayer';
import { NativeSynthesizeResult, SileroTtsNative } from './SileroTtsNative';
import { SileroModelInstaller } from './SileroModelInstaller';
import { TtsVoiceCatalog } from './TtsVoiceCatalog';
import { TtsVoiceManager, TtsVoiceRowState } from './TtsVoiceManager';
import { TtsSpeakUi } from './TtsSpeakUi';
import { TextDecorationUtil } from '../translation/TextDecorationUtil';

const DOMAIN = 0x53494C;

/**
 * 离线朗读：中文 SummerTTS、日语与 Piper 语种经 piper-plus；本机 C++ NAPI。
 */
export enum SileroSpeakFailure {
  NONE = 0,
  EMPTY = 1,
  UNSUPPORTED_LANG = 2,
  NOT_READY = 3,
  MODEL_MISSING = 4,
  ENGINE_NOT_LINKED = 5,
  MOBILE_MODEL_MISSING = 6,
  SYNTHESIZE_FAILED = 7,
  PLAYBACK_FAILED = 8,
}

/** 单次送入 TTS 后端的字符上限；超长文本按句/段分块合成后拼接播放 */
const MAX_SPEAK_CHUNK_CHARS = 280;

export interface SileroSpeakCallbacks {
  /** 合成完成、即将开始写入音频时 */
  onPlaybackStart?: () => void;
}

export class SileroTtsEngine {
  private static lastSpeakFailure: SileroSpeakFailure = SileroSpeakFailure.NONE;
  private static lastSynthesizeError: string = '';
  /** 递增后取消尚未完成的合成/播放（连点朗读） */
  private static speakEpoch: number = 0;

  static getLastSpeakFailure(): SileroSpeakFailure {
    return SileroTtsEngine.lastSpeakFailure;
  }

  static getLastSynthesizeError(): string {
    return SileroTtsEngine.lastSynthesizeError;
  }
  private static warmed: boolean = false;

  static isSupportedLang(iso: string): boolean {
    return SileroModelPaths.isSupportedIso(iso);
  }

  static init(context: common.Context): void {
    TtsVoiceManager.init(context);
  }

  static async warmUp(): Promise<void> {
    if (!TtsVoiceManager.isCapabilityOk()) {
      return;
    }
    for (let i = 0; i < SileroModelPaths.SUPPORTED_ISOS.length; i++) {
      await TtsVoiceManager.queryRowStatus(SileroModelPaths.SUPPORTED_ISOS[i]);
    }
    if (SileroTtsNative.usesSummerTts()) {
      const zhReady = await TtsVoiceManager.isVoiceReady('zh');
      if (!zhReady && await TtsVoiceManager.isRawBundledForIso('zh')) {
        hilog.info(DOMAIN, 'Silero', 'preinstall zh voice pack in background');
        hilog.info(0x0000, 'testTag', 'TTS preinstall zh voice pack');
        await TtsVoiceManager.ensureDownloaded('zh');
      }
      if (await TtsVoiceManager.isVoiceReady('zh')) {
        const filesDir = TtsVoiceManager.getFilesDir();
        if (filesDir.length > 0) {
          SileroTtsNative.syncModelRoot(filesDir);
        }
        hilog.info(DOMAIN, 'Silero', 'zh voice ready; SummerTTS loads on first speak');
      }
    }
    SileroTtsEngine.warmed = true;
  }

  /** NAPI 已加载即可进入朗读流程（合成需已链接推理库且模型已安装） */
  static isReady(): boolean {
    return TtsVoiceManager.isCapabilityOk();
  }

  static isLibraryLinked(): boolean {
    return SileroTtsNative.isSileroLibraryLinked();
  }

  static getBuildInfo(): string {
    return SileroTtsNative.isInitialized() ? SileroTtsNative.getBuildInfo() : '';
  }

  static async stop(): Promise<void> {
    SileroTtsEngine.speakEpoch++;
    SileroTtsNative.cancelSynthesis();
    await SileroPcmPlayer.stop();
  }

  static shutdown(): void {
    void SileroTtsEngine.stop();
    TtsSpeakUi.setIdle();
    SileroTtsEngine.warmed = false;
  }

  /** 按句/段切分，与翻译分块策略一致，避免单次合成过长 */
  private static splitSpeakChunks(text: string): string[] {
    if (text.length <= MAX_SPEAK_CHUNK_CHARS) {
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
        if (part.length > MAX_SPEAK_CHUNK_CHARS) {
          flushBuf();
          for (let j = 0; j < part.length; j += MAX_SPEAK_CHUNK_CHARS) {
            chunks.push(part.substring(j, j + MAX_SPEAK_CHUNK_CHARS));
          }
          continue;
        }
        if (buf.length === 0) {
          buf = part;
        } else if (buf.length + 1 + part.length <= MAX_SPEAK_CHUNK_CHARS) {
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
      if (para.length <= MAX_SPEAK_CHUNK_CHARS) {
        if (buf.length === 0) {
          buf = para;
        } else if (buf.length + 2 + para.length <= MAX_SPEAK_CHUNK_CHARS) {
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

  private static concatPcm(parts: Uint8Array[]): Uint8Array {
    let total = 0;
    for (let i = 0; i < parts.length; i++) {
      total += parts[i].byteLength;
    }
    const out = new Uint8Array(total);
    let offset = 0;
    for (let i = 0; i < parts.length; i++) {
      out.set(parts[i], offset);
      offset += parts[i].byteLength;
    }
    return out;
  }

  /**
   * 播放前处理：仅中文裁尾部静音；Piper 英文等保留句间停顿，避免误删后半句。
   */
  private static preparePcmForPlayback(pcm: Uint8Array, sampleRateHz: number, langIso: string): ArrayBuffer {
    if (pcm.byteLength < 4 || sampleRateHz <= 0) {
      return pcm.buffer;
    }
    const rawBytes = pcm.byteLength;
    let out = pcm;
    if (langIso === 'zh') {
      out = SileroTtsEngine.trimTrailingSilenceFromEnd(pcm, sampleRateHz, 380);
      SileroTtsEngine.fadeOutTail(out, sampleRateHz, 28);
    } else {
      SileroTtsEngine.fadeOutTail(out, sampleRateHz, 12);
    }
    if (out.byteLength !== rawBytes) {
      hilog.info(DOMAIN, 'Silero', 'pcm trim iso=%{public}s raw=%{public}d out=%{public}d',
        langIso, rawBytes, out.byteLength);
    }
    return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength);
  }

  /** 从末尾向前找最后一段有声，只去掉尾部静音（不裁句中停顿） */
  private static trimTrailingSilenceFromEnd(
    pcm: Uint8Array,
    sampleRateHz: number,
    threshold: number
  ): Uint8Array {
    const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength);
    const sampleCount = pcm.byteLength / 2;
    const keepTailSamples = Math.max(800, Math.floor(sampleRateHz * 0.06));
    let lastLoudIdx = -1;
    for (let i = sampleCount - 1; i >= 0; i--) {
      const s = view.getInt16(i * 2, true);
      if (Math.abs(s) > threshold) {
        lastLoudIdx = i;
        break;
      }
    }
    if (lastLoudIdx < 0) {
      return pcm;
    }
    const endSample = Math.min(sampleCount, lastLoudIdx + 1 + keepTailSamples);
    if (endSample >= sampleCount) {
      return pcm;
    }
    return pcm.subarray(0, endSample * 2);
  }

  private static fadeOutTail(pcm: Uint8Array, sampleRateHz: number, fadeMs: number): void {
    const fadeSamples = Math.min(Math.floor(sampleRateHz * fadeMs / 1000), pcm.byteLength / 2);
    if (fadeSamples < 8) {
      return;
    }
    const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength);
    const start = pcm.byteLength / 2 - fadeSamples;
    for (let i = 0; i < fadeSamples; i++) {
      const idx = (start + i) * 2;
      const scale = 1 - (i + 1) / fadeSamples;
      const s = view.getInt16(idx, true);
      view.setInt16(idx, Math.round(s * scale), true);
    }
  }

  /** 去掉零宽字符并 NFC 规范化，避免 espeak 在波兰语等语种中途截断音素 */
  private static normalizeTtsText(text: string): string {
    let out = '';
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      if (c === 0x200B || c === 0x200C || c === 0x200D || c === 0xFEFF) {
        continue;
      }
      out += text.charAt(i);
    }
    try {
      out = out.normalize('NFC');
    } catch (_e) {
      // keep unnormalized
    }
    return TextDecorationUtil.stripForTts(out);
  }

  static async speak(text: string, langIso: string, callbacks?: SileroSpeakCallbacks): Promise<boolean> {
    const epoch = ++SileroTtsEngine.speakEpoch;
    SileroTtsNative.cancelSynthesis();
    await SileroPcmPlayer.stop();
    SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.NONE;
    const body = SileroTtsEngine.normalizeTtsText(text);
    if (body.length === 0) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.EMPTY;
      return false;
    }
    if (!SileroTtsEngine.isSupportedLang(langIso)) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.UNSUPPORTED_LANG;
      return false;
    }
    if (!SileroTtsEngine.isReady()) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.NOT_READY;
      return false;
    }
    const iso = TtsVoiceCatalog.normalizeSpeakIso(langIso);
    const speakChunks = SileroTtsEngine.splitSpeakChunks(body);
    const preview = body.length > 96 ? `${body.substring(0, 96)}…` : body;
    hilog.info(DOMAIN, 'Silero', 'speak input iso=%{public}s chars=%{public}d chunks=%{public}d preview=%{public}s',
      iso, body.length, speakChunks.length, preview);
    hilog.info(0x0000, 'testTag', 'TTS speak iso=%{public}s chars=%{public}d preview=%{public}s',
      iso, body.length, preview);
    if (speakChunks.length > 1) {
      hilog.info(DOMAIN, 'Silero', 'speak split chars=%{public}d chunks=%{public}d iso=%{public}s',
        body.length, speakChunks.length, iso);
    }
    if (epoch !== SileroTtsEngine.speakEpoch) {
      return false;
    }
    await SileroModelInstaller.waitForInstallIdle();
    const modelOk = await TtsVoiceManager.ensureDownloaded(iso);
    if (!modelOk) {
      const row = await TtsVoiceManager.queryRowStatus(iso);
      if (row.state === TtsVoiceRowState.NEED_ENGINE || row.state === TtsVoiceRowState.NEED_REAL_DEVICE) {
        SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.ENGINE_NOT_LINKED;
        hilog.warn(DOMAIN, 'Silero', 'voice pack ok but engine not ready iso=%{public}s state=%{public}d',
          iso, row.state);
      } else if (row.state === TtsVoiceRowState.NEED_DOWNLOAD) {
        const filesDir = TtsVoiceManager.getFilesDir();
        if (filesDir.length > 0 && SileroModelInstaller.hasVoiceAssets(iso, filesDir) &&
          !SileroModelInstaller.hasMobileInferenceModel(iso, filesDir)) {
          SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.MOBILE_MODEL_MISSING;
        } else {
          SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.MODEL_MISSING;
        }
        hilog.warn(DOMAIN, 'Silero', 'model not installed iso=%{public}s', iso);
      } else {
        SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.MODEL_MISSING;
        hilog.warn(DOMAIN, 'Silero', 'model not ready iso=%{public}s state=%{public}d', iso, row.state);
      }
      return false;
    }
    SileroTtsNative.refreshLinkState();
    if (!SileroTtsNative.backendReadyForIso(iso)) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.ENGINE_NOT_LINKED;
      hilog.warn(DOMAIN, 'Silero',
        'engine not ready iso=%{public}s build=%{public}s summer=%{public}s piper=%{public}s',
        iso, SileroTtsNative.getBuildInfo(), String(SileroTtsNative.usesSummerTts()),
        String(SileroTtsNative.usesPiperPlus()));
      return false;
    }
    const filesDir = TtsVoiceManager.getFilesDir();
    if (filesDir.length > 0) {
      SileroTtsNative.syncModelRoot(filesDir);
    }
    if (filesDir.length > 0 && !SileroModelInstaller.hasMobileInferenceModel(iso, filesDir)) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.MOBILE_MODEL_MISSING;
      hilog.warn(DOMAIN, 'Silero', 'inference data missing iso=%{public}s — reinstall voice pack', iso);
      return false;
    }
    if (filesDir.length > 0) {
      SileroModelInstaller.ensurePiperLangConfigReady(filesDir, iso);
    }
    if (epoch !== SileroTtsEngine.speakEpoch) {
      return false;
    }
    const pcmParts: Uint8Array[] = [];
    let sampleRate = 0;
    for (let ci = 0; ci < speakChunks.length; ci++) {
      if (epoch !== SileroTtsEngine.speakEpoch) {
        return false;
      }
      const chunkText = speakChunks[ci];
      const result: NativeSynthesizeResult | undefined = await SileroTtsNative.synthesize(chunkText, iso);
      if (epoch !== SileroTtsEngine.speakEpoch) {
        return false;
      }
      if (result === undefined || !result.ok || result.pcm.byteLength < 2) {
        SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.SYNTHESIZE_FAILED;
        let errMsg: string = 'synthesize failed';
        SileroTtsEngine.lastSynthesizeError = '';
        if (result !== undefined && result.error.length > 0) {
          errMsg = result.error;
          SileroTtsEngine.lastSynthesizeError = result.error;
        }
        hilog.warn(DOMAIN, 'Silero',
          'speak chunk failed iso=%{public}s idx=%{public}d/%{public}d err=%{public}s',
          iso, ci + 1, speakChunks.length, errMsg);
        hilog.warn(0x0000, 'testTag', 'TTS speak failed iso=%{public}s err=%{public}s', iso, errMsg);
        return false;
      }
      const rate: number = result.sampleRate > 0 ? result.sampleRate : 48000;
      if (sampleRate === 0) {
        sampleRate = rate;
      } else if (rate !== sampleRate) {
        hilog.warn(DOMAIN, 'Silero', 'speak chunk rate mismatch %{public}d vs %{public}d', rate, sampleRate);
      }
      pcmParts.push(new Uint8Array(result.pcm));
    }
    SileroTtsEngine.lastSynthesizeError = '';
    const mergedPcm = SileroTtsEngine.preparePcmForPlayback(
      SileroTtsEngine.concatPcm(pcmParts),
      sampleRate > 0 ? sampleRate : 48000,
      iso
    );
    const rate: number = sampleRate > 0 ? sampleRate : 48000;
    const durMs = Math.ceil((mergedPcm.byteLength / 2) * 1000 / rate);
    hilog.info(DOMAIN, 'Silero',
      'speak pcm iso=%{public}s rate=%{public}d bytes=%{public}d durMs=%{public}d chunks=%{public}d summer=%{public}s piper=%{public}s',
      iso, rate, mergedPcm.byteLength, durMs, speakChunks.length, String(SileroTtsNative.usesSummerTts()),
      String(SileroTtsNative.usesPiperPlus()));
    hilog.info(0x0000, 'testTag',
      'TTS pcm iso=%{public}s rate=%{public}d bytes=%{public}d durMs=%{public}d chunks=%{public}d',
      iso, rate, mergedPcm.byteLength, durMs, speakChunks.length);
    if (epoch !== SileroTtsEngine.speakEpoch) {
      return false;
    }
    callbacks?.onPlaybackStart?.();
    const played = await SileroPcmPlayer.play(mergedPcm, rate);
    if (!played) {
      SileroTtsEngine.lastSpeakFailure = SileroSpeakFailure.PLAYBACK_FAILED;
      hilog.warn(DOMAIN, 'Silero', 'pcm play failed iso=%{public}s rate=%{public}d bytes=%{public}d',
        iso, rate, mergedPcm.byteLength);
      return false;
    }
    return true;
  }
}
