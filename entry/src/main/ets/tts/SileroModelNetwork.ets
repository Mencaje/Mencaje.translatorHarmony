import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SileroModelPaths } from './SileroModelPaths';

const DOMAIN = 0x53494C;
const TAG = 'SileroNet';
const CHUNK_BYTES: number = 256 * 1024;
const HTTP_TIMEOUT_MS: number = 300000;
const MIN_MODEL_BYTES: number = 1024 * 1024;

/**
 * 从 Silero 官方地址下载语音包到应用私有目录（仅鸿蒙端使用，不走系统 TTS）。
 */
export class SileroModelNetwork {
  static async downloadLangModel(
    iso: string,
    destPath: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    const url = SileroModelPaths.downloadUrlForIso(code);
    if (url.length === 0 || destPath.length === 0) {
      return false;
    }
    return await SileroModelNetwork.downloadUrlToFile(url, destPath, onProgress);
  }

  private static async downloadUrlToFile(
    url: string,
    destPath: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const parent = destPath.substring(0, destPath.lastIndexOf('/'));
    if (parent.length > 0) {
      try {
        fileIo.mkdirSync(parent, true);
      } catch (_e) {
      }
    }
    try {
      fileIo.unlinkSync(destPath);
    } catch (_e) {
    }

    const client = http.createHttp();
    let destFile: fileIo.File | undefined = undefined;
    let totalBytes = 0;
    let written = 0;

    return await new Promise<boolean>((resolve) => {
      const finish = (ok: boolean): void => {
        if (destFile !== undefined) {
          try {
            fileIo.closeSync(destFile);
          } catch (_e) {
          }
          destFile = undefined;
        }
        try {
          client.destroy();
        } catch (_e) {
        }
        resolve(ok);
      };

      client.on('headersReceive', (header: object) => {
        const h = header as Record<string, string | number | string[]>;
        const lenRaw = h['content-length'] ?? h['Content-Length'];
        if (typeof lenRaw === 'string') {
          const n = parseInt(lenRaw, 10);
          if (!Number.isNaN(n) && n > 0) {
            totalBytes = n;
          }
        } else if (typeof lenRaw === 'number' && lenRaw > 0) {
          totalBytes = lenRaw;
        }
      });

      client.on('dataReceive', (chunk: ArrayBuffer) => {
        try {
          if (destFile === undefined) {
            destFile = fileIo.openSync(destPath,
              fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          }
          const view = new Uint8Array(chunk);
          fileIo.writeSync(destFile.fd, view.buffer, { length: view.byteLength });
          written += view.byteLength;
          if (totalBytes > 0) {
            const pct = 5 + Math.floor((written * 90) / totalBytes);
            onProgress(Math.min(95, pct));
          } else {
            onProgress(Math.min(95, 5 + Math.floor(written / (512 * 1024))));
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'write chunk failed: %{public}s', JSON.stringify(e));
          finish(false);
        }
      });

      client.on('dataEnd', () => {
        onProgress(98);
        const size = SileroModelNetwork.fileSize(destPath);
        finish(size >= MIN_MODEL_BYTES);
      });

      client.requestInStream(url, {
        method: http.RequestMethod.GET,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      }, (err: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'stream request failed: %{public}s', JSON.stringify(err));
          finish(false);
        }
      });
    });
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (_e) {
      return 0;
    }
  }
}
