import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x53494C;
/** 分块写入目标间隔（毫秒）；实际会按写入耗时自适应，避免慢于实时导致 underrun */
const CHUNK_MS = 40;
/** stop 前向设备写入静音，冲刷残留样本，减轻连点残音 */
const FLUSH_SILENCE_MS = 64;

/**
 * 播放 Silero NAPI 返回的 16-bit PCM（单声道）。
 * 使用分块 write + 播放世代号，避免整段写入导致 underrun，以及连点时的 Write length < 0。
 */
export class SileroPcmPlayer {
  private static renderer: audio.AudioRenderer | undefined = undefined;
  private static playing: boolean = false;
  private static playGen: number = 0;
  private static stopPromise: Promise<void> = Promise.resolve();
  private static lastSampleRateHz: number = 16000;

  /** 使进行中的 play 循环与 write 回调失效 */
  static bumpGeneration(): void {
    SileroPcmPlayer.playGen++;
    SileroPcmPlayer.playing = false;
  }

  static async stop(): Promise<void> {
    SileroPcmPlayer.bumpGeneration();
    const prev = SileroPcmPlayer.stopPromise;
    let release!: () => void;
    SileroPcmPlayer.stopPromise = new Promise<void>((resolve) => {
      release = resolve;
    });
    await prev;
    const r = SileroPcmPlayer.renderer;
    SileroPcmPlayer.renderer = undefined;
    if (r !== undefined) {
      await SileroPcmPlayer.flushAndReleaseRenderer(r);
    }
    release();
  }

  private static async flushAndReleaseRenderer(renderer: audio.AudioRenderer): Promise<void> {
    try {
      await SileroPcmPlayer.writeSilence(renderer, SileroPcmPlayer.lastSampleRateHz, FLUSH_SILENCE_MS);
    } catch (_e) {
    }
    try {
      renderer.off('stateChange');
    } catch (_e) {
    }
    try {
      renderer.off('writeData');
    } catch (_e) {
    }
    try {
      await renderer.stop();
    } catch (_e) {
    }
    try {
      await renderer.release();
    } catch (_e) {
    }
  }

  private static async writeSilence(renderer: audio.AudioRenderer, sampleRateHz: number, ms: number): Promise<void> {
    if (ms <= 0 || sampleRateHz <= 0) {
      return;
    }
    const samples = Math.max(1, Math.floor(sampleRateHz * ms / 1000));
    const buf = new ArrayBuffer(samples * 2);
    await SileroPcmPlayer.writeChunk(renderer, buf);
  }

  static async play(pcm: ArrayBuffer, sampleRateHz: number): Promise<boolean> {
    if (pcm.byteLength < 2 || sampleRateHz <= 0) {
      return false;
    }
    await SileroPcmPlayer.stop();
    await SileroPcmPlayer.sleepMs(32);
    const session = SileroPcmPlayer.playGen;
    SileroPcmPlayer.lastSampleRateHz = sampleRateHz;
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: SileroPcmPlayer.mapSampleRate(sampleRateHz),
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
    };
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_MEDIA,
      rendererFlags: 0,
    };
    let renderer: audio.AudioRenderer;
    try {
      renderer = await audio.createAudioRenderer({
        streamInfo: streamInfo,
        rendererInfo: rendererInfo,
      });
    } catch (e) {
      hilog.error(DOMAIN, 'SileroPcm', 'createAudioRenderer failed: %{public}s', JSON.stringify(e));
      return false;
    }
    SileroPcmPlayer.renderer = renderer;
    SileroPcmPlayer.playing = true;
    renderer.on('stateChange', (_state: audio.AudioState) => {
      // 持有引用，避免系统 OnStateChange 报 “Cannot find the reference”
    });
    try {
      await renderer.start();
      if (session !== SileroPcmPlayer.playGen || !SileroPcmPlayer.playing) {
        await SileroPcmPlayer.stop();
        return false;
      }
      const pcmDurationMs = Math.ceil((pcm.byteLength / 2) * 1000 / sampleRateHz);
      const writeStartedAt = Date.now();
      const ok = await SileroPcmPlayer.writeAllChunks(renderer, pcm, sampleRateHz, session);
      if (!ok || session !== SileroPcmPlayer.playGen) {
        await SileroPcmPlayer.stop();
        return false;
      }
      const writeElapsedMs = Date.now() - writeStartedAt;
      const drainPadMs = sampleRateHz <= 22050 ? 200 : 120;
      const drainMs = Math.max(CHUNK_MS + 160, pcmDurationMs - writeElapsedMs + drainPadMs);
      await SileroPcmPlayer.sleepWhilePlaying(drainMs, session);
      if (session !== SileroPcmPlayer.playGen) {
        return false;
      }
      await SileroPcmPlayer.stop();
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'SileroPcm', 'play failed: %{public}s', JSON.stringify(e));
      await SileroPcmPlayer.stop();
      return false;
    }
  }

  private static chunkMsForRate(sampleRateHz: number): number {
    if (sampleRateHz <= 22050) {
      return 48;
    }
    return CHUNK_MS;
  }

  private static chunkBytes(sampleRateHz: number): number {
    const chunkMs = SileroPcmPlayer.chunkMsForRate(sampleRateHz);
    const samples = Math.max(160, Math.floor(sampleRateHz * chunkMs / 1000));
    return samples * 2;
  }

  private static async writeAllChunks(
    renderer: audio.AudioRenderer,
    pcm: ArrayBuffer,
    sampleRateHz: number,
    gen: number
  ): Promise<boolean> {
    const bytes = new Uint8Array(pcm);
    const chunkSize = SileroPcmPlayer.chunkBytes(sampleRateHz);
    const paceMs = SileroPcmPlayer.chunkMsForRate(sampleRateHz);
    let offset = 0;
    let totalWritten = 0;
    let primed = 0;
    while (offset < bytes.length) {
      if (!SileroPcmPlayer.playing || gen !== SileroPcmPlayer.playGen) {
        return false;
      }
      const end = Math.min(offset + chunkSize, bytes.length);
      const slice = bytes.subarray(offset, end);
      const chunkBuf = slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength);
      const t0 = Date.now();
      const n = await SileroPcmPlayer.writeChunk(renderer, chunkBuf);
      const elapsed = Date.now() - t0;
      if (n <= 0) {
        hilog.warn(DOMAIN, 'SileroPcm', 'write chunk failed off=%{public}d n=%{public}d gen=%{public}d',
          offset, n, gen);
        return false;
      }
      totalWritten += n;
      offset = end;
      if (offset < bytes.length) {
        primed++;
        if (primed <= 2) {
          continue;
        }
        const waitMs = paceMs - elapsed;
        if (waitMs > 0) {
          await SileroPcmPlayer.sleepMs(waitMs);
        }
      }
    }
    const durMs = Math.ceil((pcm.byteLength / 2) * 1000 / sampleRateHz);
    hilog.info(DOMAIN, 'SileroPcm',
      'chunks done bytes=%{public}d written=%{public}d rate=%{public}d durMs=%{public}d paceMs=%{public}d',
      pcm.byteLength, totalWritten, sampleRateHz, durMs, paceMs);
    return totalWritten > 0;
  }

  private static writeChunk(renderer: audio.AudioRenderer, chunk: ArrayBuffer): Promise<number> {
    return new Promise<number>((resolve, reject) => {
      renderer.write(chunk, (err: BusinessError, n?: number) => {
        if (err) {
          reject(err);
          return;
        }
        resolve(n ?? 0);
      });
    });
  }

  private static mapSampleRate(hz: number): audio.AudioSamplingRate {
    if (hz >= 48000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_48000;
    }
    if (hz >= 44100) {
      return audio.AudioSamplingRate.SAMPLE_RATE_44100;
    }
    if (hz >= 32000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_32000;
    }
    if (hz >= 24000) {
      return audio.AudioSamplingRate.SAMPLE_RATE_24000;
    }
    if (hz >= 22050) {
      return audio.AudioSamplingRate.SAMPLE_RATE_22050;
    }
    return audio.AudioSamplingRate.SAMPLE_RATE_16000;
  }

  private static sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }

  private static sleepWhilePlaying(ms: number, gen: number): Promise<void> {
    return new Promise<void>((resolve) => {
      const deadline = Date.now() + ms;
      const tick = (): void => {
        if (!SileroPcmPlayer.playing || gen !== SileroPcmPlayer.playGen || Date.now() >= deadline) {
          resolve();
          return;
        }
        setTimeout(tick, 40);
      };
      setTimeout(tick, 40);
    });
  }
}
