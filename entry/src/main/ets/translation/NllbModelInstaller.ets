import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ct2native from 'libctranslate2_napi.so';
import { CTranslate2Engine } from './CTranslate2Engine';
import { NllbModelPaths } from './NllbModelPaths';

const DOMAIN = 0x4E4C4C;
const UI_DOMAIN = 0x0000;
const TAG = 'NllbInstall';
const UI_TAG = 'testTag';
const CHUNK_BYTES: number = 512 * 1024;
/** int8 CT2 包压缩后通常 400–700MB */
const ZIP_MIN_BYTES: number = 80 * 1024 * 1024;
/** 与打包的 nllb-200-distilled-600M int8 model.bin (~2.46GB) 对齐，避免残缺拷贝误判为已安装 */
const MODEL_BIN_MIN_BYTES: number = 2000 * 1024 * 1024;

export enum NllbInstallFailure {
  NONE = 0,
  BUSY = 1,
  NOT_BUNDLED = 2,
  COPY_FAILED = 3,
}

export class NllbModelInstaller {
  private static installLock: boolean = false;
  private static lastFailure: NllbInstallFailure = NllbInstallFailure.NONE;
  private static lastFailureDetail: string = '';
  private static startupInstallPromise: Promise<boolean> | null = null;
  private static startupInstallFinished: boolean = false;
  private static appContext: common.Context | null = null;

  static readonly RAW_ZIP_NAME: string = 'nllb200_distilled_600m.zip';
  static readonly BUNDLE_DIR_NAME: string = 'nllb-200-distilled-600M';
  static readonly MODEL_FILE_NAMES: string[] =
    ['config.json', 'model.bin', 'shared_vocabulary.json', 'sentencepiece.bpe.model'];

  static getLastFailure(): NllbInstallFailure {
    return NllbModelInstaller.lastFailure;
  }

  static getLastFailureDetail(): string {
    return NllbModelInstaller.lastFailureDetail;
  }

  static isInstalled(filesDir: string): boolean {
    const dir = NllbModelPaths.modelRoot(filesDir);
    if (dir.length === 0) {
      return false;
    }
    try {
      if (!ct2native.isModelPresent(dir)) {
        return false;
      }
      const bin = `${dir}/model.bin`;
      if (NllbModelInstaller.pathExists(bin)) {
        return NllbModelInstaller.fileSize(bin) >= MODEL_BIN_MIN_BYTES;
      }
      return NllbModelInstaller.pathExists(`${dir}/model.bin.index`);
    } catch (_e) {
      return false;
    }
  }

  static canOpenRawZip(context: common.Context): boolean {
    return NllbModelInstaller.canOpenRawResfileEntry(context, NllbModelInstaller.RAW_ZIP_NAME);
  }

  static canOpenRawResfileEntry(context: common.Context, rawPath: string): boolean {
    try {
      context.resourceManager.getRawFdSync(rawPath);
      context.resourceManager.closeRawFdSync(rawPath);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 在 resourceDir 下探测可读的打包模型目录（含 resfile 子路径） */
  static resolveBundledFilesystemDir(context: common.Context): string {
    const candidates = NllbModelPaths.bundledModelDirCandidates(context.resourceDir ?? '');
    for (let i = 0; i < candidates.length; i++) {
      const dir = candidates[i];
      const bin = `${dir}/model.bin`;
      if (NllbModelInstaller.pathExists(bin) &&
        NllbModelInstaller.fileSize(bin) >= MODEL_BIN_MIN_BYTES) {
        return dir;
      }
    }
    return '';
  }

  private static finishStartupInstall(ok: boolean): void {
    CTranslate2Engine.refreshModelPresence();
    const ready = CTranslate2Engine.isReadyForOffline();
    NllbModelInstaller.startupInstallFinished = true;
    NllbModelInstaller.startupInstallPromise = Promise.resolve(ready);
    hilog.info(DOMAIN, TAG, 'NLLB startup finish ok=%{public}s ready=%{public}s dir=%{public}s',
      String(ok), String(ready), CTranslate2Engine.getModelDir());
    hilog.info(UI_DOMAIN, UI_TAG, 'NLLB startup ready=%{public}s dir=%{public}s',
      String(ready), CTranslate2Engine.getModelDir());
    if (ready) {
      CTranslate2Engine.preloadInBackground();
    }
  }

  /** 不阻塞 whenInstallDone；仅把 resfile 模型同步到 filesDir */
  private static runBackgroundCopyToFilesDir(context: common.Context): void {
    if (NllbModelInstaller.installLock) {
      return;
    }
    hilog.info(UI_DOMAIN, UI_TAG, 'NLLB background: copying model to private storage…');
    NllbModelInstaller.installIfNeeded(context, (percent: number) => {
      const pct = Math.floor(percent / 10) * 10;
      if (pct > 0 && pct % 20 === 0) {
        hilog.info(UI_DOMAIN, UI_TAG, 'NLLB background copy %{public}d%%', pct);
      }
    }, (ok: boolean) => {
      CTranslate2Engine.refreshModelPresence();
      hilog.info(DOMAIN, TAG, 'NLLB background copy done ok=%{public}s dir=%{public}s',
        String(ok), CTranslate2Engine.getModelDir());
    });
  }

  private static runStartupInstallTask(context: common.Context): void {
    let lastLoggedPct = -1;
    NllbModelInstaller.startupInstallPromise = new Promise<boolean>((resolve) => {
      NllbModelInstaller.installIfNeeded(context, (percent: number) => {
        const pct = Math.floor(percent / 10) * 10;
        if (pct >= lastLoggedPct + 10) {
          lastLoggedPct = pct;
          hilog.info(UI_DOMAIN, UI_TAG, 'NLLB copy progress %{public}d%%', pct);
        }
      }, (_ok: boolean) => {
        CTranslate2Engine.refreshModelPresence();
        NllbModelInstaller.startupInstallFinished = true;
        const ready = CTranslate2Engine.isReadyForOffline();
        const detail = NllbModelInstaller.getLastFailureDetail();
        hilog.info(DOMAIN, TAG,
          'NLLB startup install done ready=%{public}s installed=%{public}s dir=%{public}s fail=%{public}s',
          String(ready), String(CTranslate2Engine.isModelInstalled()), CTranslate2Engine.getModelDir(), detail);
        hilog.info(UI_DOMAIN, UI_TAG, 'NLLB startup install done ready=%{public}s', String(ready));
        if (!ready) {
          if (!CTranslate2Engine.isCt2LibraryLinked()) {
            hilog.error(UI_DOMAIN, UI_TAG,
              'NLLB not ready: CT2 not linked (%{public}s). Clean+Rebuild in DevEco, reinstall HAP on phone.',
              ct2native.getBuildInfo());
          } else if (!CTranslate2Engine.isModelInstalled()) {
            hilog.error(UI_DOMAIN, UI_TAG, 'NLLB model incomplete: %{public}s', detail);
          } else {
            hilog.error(UI_DOMAIN, UI_TAG, 'NLLB not ready: %{public}s', detail);
          }
        }
        if (ready) {
          CTranslate2Engine.preloadInBackground();
        }
        resolve(ready);
      });
    });
  }

  static prepareModelDirectories(context: common.Context): void {
    NllbModelInstaller.ensureDir(`${context.filesDir}/models`);
    NllbModelInstaller.ensureDir(NllbModelPaths.modelRoot(context.filesDir));
  }

  static isBundledInHap(context: common.Context): boolean {
    return NllbModelInstaller.isRawBundledInHap(context);
  }

  /** 应用启动时从 HAP 解压（用户无需手动下载） */
  static beginInstallOnStartup(context: common.Context): void {
    NllbModelInstaller.appContext = context;
    NllbModelInstaller.prepareModelDirectories(context);
    const fsBundled = NllbModelInstaller.resolveBundledFilesystemDir(context);
    hilog.info(DOMAIN, TAG,
      'NLLB filesDir=%{public}s resourceDir=%{public}s fsBundled=%{public}s ct2=%{public}s',
      context.filesDir, context.resourceDir, fsBundled, String(CTranslate2Engine.isModelInstalled()));
    const bundled = NllbModelInstaller.isRawBundledInHap(context);
    hilog.info(UI_DOMAIN, UI_TAG,
      'NLLB filesDir=%{public}s resourceDir=%{public}s fsBundled=%{public}s bundled=%{public}s',
      context.filesDir, context.resourceDir ?? '', fsBundled, String(bundled));
    if (NllbModelInstaller.startupInstallPromise !== null) {
      return;
    }
    CTranslate2Engine.refreshModelPresence();
    if (CTranslate2Engine.isReadyForOffline()) {
      NllbModelInstaller.finishStartupInstall(true);
      hilog.info(DOMAIN, TAG, 'NLLB ready (filesDir or bundled resfile)');
      if (!NllbModelInstaller.isInstalled(context.filesDir) &&
        NllbModelInstaller.isRawBundledInHap(context)) {
        hilog.info(DOMAIN, TAG, 'NLLB background copy to filesDir');
        NllbModelInstaller.runBackgroundCopyToFilesDir(context);
      }
      return;
    }
    if (NllbModelInstaller.isRawBundledInHap(context)) {
      hilog.info(DOMAIN, TAG, 'NLLB bundled in HAP; install to filesDir (zip decompress or resfile copy)');
      hilog.info(UI_DOMAIN, UI_TAG, 'NLLB first launch: preparing model (~1–3 min), keep app open…');
      NllbModelInstaller.runStartupInstallTask(context);
      return;
    }
    NllbModelInstaller.finishStartupInstall(false);
    hilog.warn(DOMAIN, TAG,
      'NLLB slim HAP: run prepare_nllb_for_hap.ps1 then Clean+Rebuild, or import in Settings');
    hilog.warn(UI_DOMAIN, UI_TAG,
      'NLLB not in HAP — install full package or Settings → offline model');
  }

  static whenInstallDone(): Promise<boolean> {
    const readyNow = (): boolean => {
      CTranslate2Engine.refreshModelPresence();
      return CTranslate2Engine.isReadyForOffline();
    };
    if (NllbModelInstaller.startupInstallPromise !== null) {
      return NllbModelInstaller.startupInstallPromise.then(() => readyNow());
    }
    if (NllbModelInstaller.startupInstallFinished) {
      return Promise.resolve(readyNow());
    }
    return Promise.resolve(false);
  }

  static isInstallInProgress(): boolean {
    return NllbModelInstaller.startupInstallPromise !== null &&
      !NllbModelInstaller.startupInstallFinished;
  }

  static isRawBundledInHap(context: common.Context): boolean {
    if (NllbModelInstaller.resolveBundledFilesystemDir(context).length > 0) {
      return true;
    }
    const resZip = `${context.resourceDir}/${NllbModelInstaller.RAW_ZIP_NAME}`;
    if (NllbModelInstaller.pathExists(resZip) && NllbModelInstaller.fileSize(resZip) >= ZIP_MIN_BYTES) {
      return true;
    }
    if (NllbModelInstaller.canOpenRawZip(context)) {
      return true;
    }
    const rawBin = `${NllbModelInstaller.BUNDLE_DIR_NAME}/model.bin`;
    if (NllbModelInstaller.canOpenRawResfileEntry(context, rawBin)) {
      return true;
    }
    return NllbModelInstaller.canOpenRawResfileEntry(context,
      `${NllbModelInstaller.BUNDLE_DIR_NAME}/config.json`);
  }

  static installIfNeeded(
    context: common.Context,
    onProgress: (percent: number) => void,
    onDone: (ok: boolean) => void,
  ): void {
    if (NllbModelInstaller.installLock) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.BUSY;
      onDone(false);
      return;
    }
    NllbModelInstaller.lastFailure = NllbInstallFailure.NONE;
    NllbModelInstaller.lastFailureDetail = '';
    if (NllbModelInstaller.isInstalled(context.filesDir)) {
      CTranslate2Engine.refreshModelPresence();
      onProgress(100);
      onDone(true);
      return;
    }
    NllbModelInstaller.installLock = true;
    const task = async (): Promise<boolean> => {
      try {
        if (NllbModelInstaller.canOpenRawZip(context) ||
          NllbModelInstaller.pathExists(`${context.resourceDir}/${NllbModelInstaller.RAW_ZIP_NAME}`)) {
          hilog.info(DOMAIN, TAG, 'NLLB install try bundled zip (rawfile)');
          const fromZip = await NllbModelInstaller.installFromBundledZip(context, onProgress);
          if (fromZip) {
            return true;
          }
        }
        const bundleSrc = NllbModelInstaller.resolveBundledFilesystemDir(context);
        if (bundleSrc.length > 0) {
          hilog.info(DOMAIN, TAG, 'NLLB install try filesystem copy from %{public}s', bundleSrc);
          const fromFs = await NllbModelInstaller.installFromResfileDir(context, bundleSrc, onProgress);
          if (fromFs) {
            return true;
          }
          hilog.warn(DOMAIN, TAG, 'NLLB filesystem copy failed, try resfile raw fd');
        }
        const rawBin = `${NllbModelInstaller.BUNDLE_DIR_NAME}/model.bin`;
        if (NllbModelInstaller.canOpenRawResfileEntry(context, rawBin)) {
          hilog.info(DOMAIN, TAG, 'NLLB install try resfile raw entries');
          return await NllbModelInstaller.installFromResfileRawEntries(context, onProgress);
        }
        hilog.info(DOMAIN, TAG, 'NLLB install try bundled zip (fallback)');
        return await NllbModelInstaller.installFromBundledZip(context, onProgress);
      } catch (e) {
        NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
        NllbModelInstaller.lastFailureDetail = JSON.stringify(e);
        return false;
      } finally {
        NllbModelInstaller.installLock = false;
      }
    };
    task().then((ok: boolean) => {
      onProgress(ok ? 100 : 0);
      onDone(ok);
    });
  }

  static async installFromPickerUris(
    context: common.Context,
    uris: string[],
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    if (uris.length === 0) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.NOT_BUNDLED;
      NllbModelInstaller.lastFailureDetail = 'no files selected';
      return false;
    }
    NllbModelInstaller.prepareModelDirectories(context);
    const destRoot = NllbModelPaths.modelRoot(context.filesDir);
    NllbModelInstaller.removePathQuiet(destRoot);
    NllbModelInstaller.ensureDir(destRoot);
    onProgress(1);
    let copied = 0;
    for (let i = 0; i < uris.length; i++) {
      const name = NllbModelInstaller.basenameFromUri(uris[i]);
      if (!NllbModelInstaller.MODEL_FILE_NAMES.includes(name)) {
        continue;
      }
      const dest = `${destRoot}/${name}`;
      const ok = await NllbModelInstaller.copyUriToPath(uris[i], dest, (p: number) => {
        const base = 5 + Math.floor((i * 85) / Math.max(1, uris.length));
        onProgress(base + Math.floor(p * 0.85 / Math.max(1, uris.length)));
      });
      if (!ok) {
        NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
        NllbModelInstaller.lastFailureDetail = `import failed: ${name}`;
        return false;
      }
      copied++;
    }
    if (copied < NllbModelInstaller.MODEL_FILE_NAMES.length) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.NOT_BUNDLED;
      NllbModelInstaller.lastFailureDetail =
        'select config.json, model.bin, shared_vocabulary.json, sentencepiece.bpe.model';
      return false;
    }
    if (!NllbModelInstaller.isInstalled(context.filesDir)) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
      NllbModelInstaller.lastFailureDetail = 'import incomplete — need all 4 model files';
      return false;
    }
    CTranslate2Engine.refreshModelPresence();
    onProgress(100);
    hilog.info(DOMAIN, TAG, 'NLLB imported from picker to %{public}s', destRoot);
    return true;
  }

  private static async installFromResfileRawEntries(
    context: common.Context,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const destRoot = NllbModelPaths.modelRoot(context.filesDir);
    NllbModelInstaller.ensureDir(`${context.filesDir}/models`);
    NllbModelInstaller.removePathQuiet(destRoot);
    NllbModelInstaller.ensureDir(destRoot);
    onProgress(2);
    const names = NllbModelInstaller.MODEL_FILE_NAMES;
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const rawPath = `${NllbModelInstaller.BUNDLE_DIR_NAME}/${name}`;
      const dest = `${destRoot}/${name}`;
      const minBytes = name === 'model.bin' ? MODEL_BIN_MIN_BYTES : 1;
      const ok = await NllbModelInstaller.copyRawFileChunked(
        context, rawPath, dest, (p: number) => {
          const base = 5 + Math.floor((i * 90) / Math.max(1, names.length));
          onProgress(base + Math.floor(p * 0.9 / Math.max(1, names.length)));
        }, minBytes);
      if (!ok) {
        NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
        NllbModelInstaller.lastFailureDetail = `raw copy failed: ${rawPath}`;
        return false;
      }
    }
    if (!NllbModelInstaller.isInstalled(context.filesDir)) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
      NllbModelInstaller.lastFailureDetail = 'raw resfile copy incomplete';
      return false;
    }
    CTranslate2Engine.refreshModelPresence();
    onProgress(100);
    hilog.info(DOMAIN, TAG, 'NLLB copied from resfile(raw) to %{public}s', destRoot);
    return true;
  }

  private static async installFromResfileDir(
    context: common.Context,
    srcRoot: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const destRoot = NllbModelPaths.modelRoot(context.filesDir);
    NllbModelInstaller.ensureDir(`${context.filesDir}/models`);
    NllbModelInstaller.removePathQuiet(destRoot);
    NllbModelInstaller.ensureDir(destRoot);
    onProgress(2);
    const names = NllbModelInstaller.MODEL_FILE_NAMES;
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const src = `${srcRoot}/${name}`;
      const dest = `${destRoot}/${name}`;
      if (!NllbModelInstaller.pathExists(src)) {
        NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
        NllbModelInstaller.lastFailureDetail = `bundle missing: ${name}`;
        return false;
      }
      const minBytes = name === 'model.bin' ? MODEL_BIN_MIN_BYTES : 1;
      const ok = await NllbModelInstaller.copyFileChunked(src, dest, (p: number) => {
        const base = 5 + Math.floor((i * 90) / Math.max(1, names.length));
        onProgress(base + Math.floor(p * 0.9 / Math.max(1, names.length)));
      }, minBytes);
      if (!ok) {
        NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
        NllbModelInstaller.lastFailureDetail = `resfile copy failed: ${name}`;
        return false;
      }
    }
    if (!NllbModelInstaller.isInstalled(context.filesDir)) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
      NllbModelInstaller.lastFailureDetail = 'resfile copy incomplete (model.bin too small?)';
      return false;
    }
    CTranslate2Engine.refreshModelPresence();
    onProgress(100);
    hilog.info(DOMAIN, TAG, 'NLLB copied from resfile to %{public}s', destRoot);
    return true;
  }

  private static async copyTreeRecursive(
    srcDir: string,
    destDir: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    try {
      const st = fileIo.statSync(srcDir);
      if (!st.isDirectory()) {
        NllbModelInstaller.ensureDir(destDir.substring(0, destDir.lastIndexOf('/')));
        const base = srcDir.substring(srcDir.lastIndexOf('/') + 1);
        const minBytes = base === 'model.bin' ? MODEL_BIN_MIN_BYTES : 1;
        return await NllbModelInstaller.copyFileChunked(srcDir, destDir, onProgress, minBytes);
      }
      NllbModelInstaller.ensureDir(destDir);
      const names = fileIo.listFileSync(srcDir);
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        const src = `${srcDir}/${name}`;
        const dst = `${destDir}/${name}`;
        const childOk = await NllbModelInstaller.copyTreeRecursive(src, dst, (p: number) => {
          const base = 5 + Math.floor((i * 90) / Math.max(1, names.length));
          onProgress(base + Math.floor(p * 0.9 / Math.max(1, names.length)));
        });
        if (!childOk) {
          return false;
        }
      }
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copyTree %{public}s', JSON.stringify(e));
      return false;
    }
  }

  private static async installFromBundledZip(
    context: common.Context,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const modelsParent = `${context.filesDir}/models`;
    const modelRoot = NllbModelPaths.modelRoot(context.filesDir);
    const zipPath = `${context.filesDir}/${NllbModelInstaller.RAW_ZIP_NAME}`;
    NllbModelInstaller.ensureDir(modelsParent);
    onProgress(1);

    let haveZip = false;
    const resZip = `${context.resourceDir}/${NllbModelInstaller.RAW_ZIP_NAME}`;
    if (NllbModelInstaller.pathExists(resZip) && NllbModelInstaller.fileSize(resZip) >= ZIP_MIN_BYTES) {
      haveZip = await NllbModelInstaller.copyFileChunked(resZip, zipPath, (p: number) => {
        onProgress(2 + Math.floor(p * 0.38));
      }, ZIP_MIN_BYTES);
    } else if (NllbModelInstaller.canOpenRawZip(context)) {
      NllbModelInstaller.removePathQuiet(zipPath);
      haveZip = await NllbModelInstaller.copyRawFileChunked(
        context, NllbModelInstaller.RAW_ZIP_NAME, zipPath, (p: number) => {
          onProgress(2 + Math.floor(p * 0.38));
        }, ZIP_MIN_BYTES);
    }
    if (!haveZip || !NllbModelInstaller.zipLooksValid(zipPath)) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.NOT_BUNDLED;
      NllbModelInstaller.lastFailureDetail =
        `${NllbModelInstaller.RAW_ZIP_NAME} missing in HAP — use hdc push or pack rawfile`;
      hilog.error(DOMAIN, TAG, '%{public}s', NllbModelInstaller.lastFailureDetail);
      return false;
    }

    onProgress(42);
    NllbModelInstaller.removePathQuiet(modelRoot);
    NllbModelInstaller.ensureDir(modelsParent);
    try {
      await zlib.decompressFile(zipPath, modelsParent, {});
    } catch (e) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
      NllbModelInstaller.lastFailureDetail = `decompress: ${JSON.stringify(e)}`;
      return false;
    }
    onProgress(92);
    if (!NllbModelInstaller.isInstalled(context.filesDir)) {
      NllbModelInstaller.lastFailure = NllbInstallFailure.COPY_FAILED;
      NllbModelInstaller.lastFailureDetail =
        `after unzip expected ${NllbModelPaths.MODEL_FOLDER_NAME}/ under files/models/`;
      return false;
    }
    CTranslate2Engine.refreshModelPresence();
    onProgress(100);
    hilog.info(DOMAIN, TAG, 'NLLB model ready at %{public}s', modelRoot);
    return true;
  }

  private static basenameFromUri(uri: string): string {
    try {
      const path = new fileUri.FileUri(uri).path;
      const idx = path.lastIndexOf('/');
      return idx >= 0 ? path.substring(idx + 1) : path;
    } catch (_e) {
      const slash = uri.lastIndexOf('/');
      const raw = slash >= 0 ? uri.substring(slash + 1) : uri;
      try {
        return decodeURIComponent(raw);
      } catch (_e2) {
        return raw;
      }
    }
  }

  private static async copyUriToPath(
    uri: string,
    destPath: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    NllbModelInstaller.removePathQuiet(destPath);
    let src: fileIo.File | undefined = undefined;
    let dest: fileIo.File | undefined = undefined;
    try {
      src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      dest = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const buf = new ArrayBuffer(CHUNK_BYTES);
      let copied = 0;
      while (true) {
        const n = fileIo.readSync(src.fd, buf);
        if (n <= 0) {
          break;
        }
        fileIo.writeSync(dest.fd, buf, { length: n });
        copied += n;
        if (copied > 0 && copied % (CHUNK_BYTES * 8) === 0) {
          onProgress(Math.min(99, Math.floor(copied / (1024 * 1024)) % 100));
        }
      }
      const size = NllbModelInstaller.fileSize(destPath);
      if (NllbModelInstaller.basenameFromUri(uri) === 'model.bin') {
        return size >= 50000000;
      }
      return size > 0;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copyUri %{public}s', JSON.stringify(e));
      return false;
    } finally {
      if (src !== undefined) {
        try {
          fileIo.closeSync(src);
        } catch (_e) {
        }
      }
      if (dest !== undefined) {
        try {
          fileIo.closeSync(dest);
        } catch (_e) {
        }
      }
    }
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true);
    } catch (_e) {
    }
  }

  private static removePathQuiet(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      const st = fileIo.statSync(path);
      if (st.isDirectory()) {
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (_e) {
    }
  }

  private static pathExists(path: string): boolean {
    try {
      fileIo.accessSync(path);
      return true;
    } catch (_e) {
      return false;
    }
  }

  private static fileSize(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (_e) {
      return 0;
    }
  }

  private static zipLooksValid(path: string): boolean {
    if (NllbModelInstaller.fileSize(path) < ZIP_MIN_BYTES) {
      return false;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const head = new ArrayBuffer(4);
      if (fileIo.readSync(file.fd, head) < 2) {
        return false;
      }
      const sig = new Uint8Array(head);
      return sig[0] === 0x50 && sig[1] === 0x4B;
    } catch (_e) {
      return false;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (_e) {
        }
      }
    }
  }

  private static async copyFileChunked(
    srcPath: string,
    destPath: string,
    onProgress: (percent: number) => void,
    minBytes: number = 1,
  ): Promise<boolean> {
    NllbModelInstaller.removePathQuiet(destPath);
    let src: fileIo.File | undefined = undefined;
    let dest: fileIo.File | undefined = undefined;
    try {
      const total = NllbModelInstaller.fileSize(srcPath);
      src = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      dest = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const buf = new ArrayBuffer(CHUNK_BYTES);
      let copied = 0;
      while (true) {
        const n = fileIo.readSync(src.fd, buf);
        if (n <= 0) {
          break;
        }
        fileIo.writeSync(dest.fd, buf, { length: n });
        copied += n;
        if (total > 0) {
          onProgress(Math.min(99, Math.floor((copied * 100) / total)));
        }
      }
      const outSize = NllbModelInstaller.fileSize(destPath);
      if (total > 0 && outSize < total) {
        hilog.error(DOMAIN, TAG, 'incomplete copy %{public}s: %{public}d/%{public}d',
          destPath, outSize, total);
        return false;
      }
      return copied > 0 && outSize >= minBytes;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copyFileChunked %{public}s', JSON.stringify(e));
      return false;
    } finally {
      if (src !== undefined) {
        try {
          fileIo.closeSync(src);
        } catch (_e) {
        }
      }
      if (dest !== undefined) {
        try {
          fileIo.closeSync(dest);
        } catch (_e) {
        }
      }
    }
  }

  private static async copyRawFileChunked(
    context: common.Context,
    rawName: string,
    destPath: string,
    onProgress: (percent: number) => void,
    minBytes: number = ZIP_MIN_BYTES,
  ): Promise<boolean> {
    NllbModelInstaller.removePathQuiet(destPath);
    const rm = context.resourceManager;
    let rawFd: resourceManager.RawFileDescriptor | undefined = undefined;
    let dest: fileIo.File | undefined = undefined;
    try {
      rawFd = rm.getRawFdSync(rawName);
      const total = rawFd.length;
      if (total <= 0) {
        return false;
      }
      dest = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.lseek(rawFd.fd, rawFd.offset, fileIo.WhenceType.SEEK_SET);
      let remaining = total;
      let written = 0;
      const buf = new ArrayBuffer(CHUNK_BYTES);
      while (remaining > 0) {
        const want = Math.min(CHUNK_BYTES, remaining);
        const n = fileIo.readSync(rawFd.fd, buf, { length: want });
        if (n <= 0) {
          break;
        }
        fileIo.writeSync(dest.fd, buf, { length: n });
        written += n;
        remaining -= n;
        onProgress(Math.min(99, Math.floor((written * 100) / total)));
      }
      return written >= minBytes;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copyRaw %{public}s', JSON.stringify(e));
      return false;
    } finally {
      try {
        rm.closeRawFdSync(rawName);
      } catch (_e) {
      }
      if (dest !== undefined) {
        try {
          fileIo.closeSync(dest);
        } catch (_e) {
        }
      }
    }
  }
}
