import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OcrLine, OcrPage } from './OcrLine';

const DOMAIN = 0x4F4352; // OCR

/** 与 CameraTranslate 中 toast 资源对应 */
export const OCR_UNAVAILABLE_CODE = 'OCR_UNAVAILABLE';

/**
 * 鸿蒙 Core Vision Kit 文字识别（对齐 Android ML Kit OcrHelper）。
 * 须 SystemCapability.AI.OCR.TextRecognition，模拟器上模块常为 undefined，请用华为真机。
 */
export class OcrHelper {
  private static initialized: boolean = false;
  private static initPromise: Promise<void> | null = null;

  static isOcrSupported(): boolean {
    try {
      return canIUse('SystemCapability.AI.OCR.TextRecognition');
    } catch (_cap) {
      return false;
    }
  }

  static async ensureInit(): Promise<void> {
    if (!OcrHelper.isOcrSupported()) {
      throw new Error(OCR_UNAVAILABLE_CODE);
    }
    if (OcrHelper.initialized) {
      return;
    }
    if (OcrHelper.initPromise !== null) {
      return OcrHelper.initPromise;
    }
    OcrHelper.initPromise = (async () => {
      try {
        const ok: boolean = await textRecognition.init();
        if (!ok) {
          throw new Error(OCR_UNAVAILABLE_CODE);
        }
        OcrHelper.initialized = true;
      } catch (err) {
        hilog.error(DOMAIN, 'OCR', 'init failed: %{public}s', JSON.stringify(err));
        throw new Error(OCR_UNAVAILABLE_CODE);
      } finally {
        OcrHelper.initPromise = null;
      }
    })();
    return OcrHelper.initPromise;
  }

  static async release(): Promise<void> {
    if (!OcrHelper.isOcrSupported() || !OcrHelper.initialized) {
      return;
    }
    try {
      await textRecognition.release();
    } catch (err) {
      hilog.warn(DOMAIN, 'OCR', 'release: %{public}s', JSON.stringify(err));
    }
    OcrHelper.initialized = false;
  }

  static async recognizeFromUri(uri: string): Promise<OcrPage> {
    const pm = await OcrHelper.loadPixelMapFromUri(uri);
    if (pm === null) {
      throw new Error('无法读取图片');
    }
    try {
      return await OcrHelper.recognizeFromPixelMap(pm);
    } finally {
      pm.release();
    }
  }

  /**
   * 相册 PhotoViewPicker 返回的 URI 须用 fd 创建 ImageSource；
   * 相机 resultUri 在部分机型上可直接传 uri，故 fd 失败时再回退。
   */
  private static async loadPixelMapFromUri(uri: string): Promise<image.PixelMap | null> {
    let opened: fileIo.File | undefined;
    try {
      opened = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source = image.createImageSource(opened.fd);
      if (source === undefined) {
        return null;
      }
      const pm = await source.createPixelMap();
      source.release();
      return pm;
    } catch (eFd) {
      hilog.warn(DOMAIN, 'OCR', 'load via fd failed: %{public}s', JSON.stringify(eFd));
      try {
        const source = image.createImageSource(uri);
        if (source === undefined) {
          return null;
        }
        const pm = await source.createPixelMap();
        source.release();
        return pm;
      } catch (eUri) {
        hilog.error(DOMAIN, 'OCR', 'loadPixelMap failed: %{public}s', JSON.stringify(eUri));
        return null;
      }
    } finally {
      if (opened !== undefined) {
        try {
          fileIo.closeSync(opened);
        } catch (_closeErr) {
          // ignore
        }
      }
    }
  }

  static async recognizeFromPixelMap(pm: image.PixelMap): Promise<OcrPage> {
    await OcrHelper.ensureInit();
    if (!OcrHelper.isOcrSupported()) {
      throw new Error(OCR_UNAVAILABLE_CODE);
    }
    const visionInfo: textRecognition.VisionInfo = { pixelMap: pm };
    const config: textRecognition.TextRecognitionConfiguration = {
      isDirectionDetectionSupported: false,
    };
    let data: textRecognition.TextRecognitionResult;
    try {
      data = await textRecognition.recognizeText(visionInfo, config);
    } catch (err) {
      hilog.error(DOMAIN, 'OCR', 'recognizeText failed: %{public}s', JSON.stringify(err));
      throw new Error(OCR_UNAVAILABLE_CODE);
    }
    const full: string = (data.value ?? '').trim();
    const lines = OcrHelper.extractLinesFromText(full);
    return new OcrPage(full, lines);
  }

  private static extractLinesFromText(full: string): OcrLine[] {
    const raw: OcrLine[] = [];
    const parts = full.split('\n');
    for (let i = 0; i < parts.length; i++) {
      const t = parts[i].trim();
      if (t.length > 0) {
        const top = i * 24;
        raw.push(new OcrLine(t, top, 0, top + 20, 0));
      }
    }
    if (raw.length > 0) {
      return OcrHelper.sortLines(raw);
    }
    if (full.length > 0) {
      raw.push(new OcrLine(full, 0, 0, 20, 0));
    }
    return raw;
  }

  private static sortLines(raw: OcrLine[]): OcrLine[] {
    const heights: number[] = [];
    for (let i = 0; i < raw.length; i++) {
      heights.push(Math.max(1, raw[i].bottom - raw[i].top));
    }
    let sum = 0;
    for (let i = 0; i < heights.length; i++) {
      sum += heights[i];
    }
    const avgH = heights.length > 0 ? sum / heights.length : 16;
    const band = Math.min(28, Math.max(6, Math.floor(avgH * 0.55)));
    const copy = raw.slice();
    copy.sort((a, b) => {
      const rowA = Math.floor(a.centerY / band) * band;
      const rowB = Math.floor(b.centerY / band) * band;
      if (rowA !== rowB) {
        return rowA - rowB;
      }
      if (a.centerX !== b.centerX) {
        return a.centerX - b.centerX;
      }
      if (a.top !== b.top) {
        return a.top - b.top;
      }
      return a.left - b.left;
    });
    return copy;
  }

  static linesToDisplayText(lines: OcrLine[]): string {
    const parts: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].text.trim();
      if (t.length > 0) {
        parts.push(t);
      }
    }
    return parts.join('\n');
  }
}
