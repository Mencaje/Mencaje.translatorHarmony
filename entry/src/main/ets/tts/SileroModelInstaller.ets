import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SileroModelPaths } from './SileroModelPaths';
import { SileroTtsNative } from './SileroTtsNative';
import { TtsVoiceCatalog } from './TtsVoiceCatalog';

const DOMAIN = 0x53494C;
const TAG = 'SileroInstall';
/** 与 EntryAbility 相同，便于在 HiLog 里按 testTag 过滤安装过程 */
const LOG_DOMAIN_UI = 0x0000;
const LOG_TAG_UI = 'testTag';
const CHUNK_BYTES: number = 256 * 1024;
const MIN_MODEL_BYTES: number = 1024 * 1024;
const RHVOICE_ZIP_MIN_BYTES: number = 512 * 1024;
const PIPER_JA_ZIP_MIN_BYTES: number = 50 * 1024 * 1024;
/** OpenJTalk sys.dic ~100MB；unk.dic 通常仅数 KB，勿与 sys.dic 同阈值（见 silero_tts_piperplus.cpp） */
const PIPER_JA_SYS_DIC_MIN_BYTES: number = 64 * 1024;
const PIPER_JA_UNK_DIC_MIN_BYTES: number = 1024;
/** espeak-ng-data/en_dict 存在且非空即视为 espeak 词典就绪 */
const ESPEAK_MARKER_MIN_BYTES: number = 1024;
/** resfile/espeakdata.zip 约 8–12MB；勿用 PIPER_JA_ZIP_MIN_BYTES 校验 */
const ESPEAK_ZIP_MIN_BYTES: number = 4 * 1024 * 1024;

export enum SileroInstallFailure {
  NONE = 0,
  BUSY = 1,
  NOT_BUNDLED = 2,
  COPY_FAILED = 3,
  NETWORK_FAILED = 4,
  MOBILE_MISSING = 5,
}

/**
 * 从 rawfile 安装离线语音数据到 filesDir/silero_tts/（SummerTTS / piper-plus）。
 */
export class SileroModelInstaller {
  private static installLock: boolean = false;
  private static lastFailure: SileroInstallFailure = SileroInstallFailure.NONE;
  private static lastFailureDetail: string = '';

  static getLastFailure(): SileroInstallFailure {
    return SileroModelInstaller.lastFailure;
  }

  static getLastFailureDetail(): string {
    return SileroModelInstaller.lastFailureDetail;
  }

  static recordInstallIncomplete(iso: string, detail: string): void {
    SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
      `${iso}: ${detail}`);
  }

  private static setFailure(kind: SileroInstallFailure, detail: string): void {
    SileroModelInstaller.lastFailure = kind;
    SileroModelInstaller.lastFailureDetail = detail;
    hilog.error(LOG_DOMAIN_UI, LOG_TAG_UI, 'install failed kind=%{public}d %{public}s',
      kind, detail);
  }

  static hasLangModel(iso: string, filesDir?: string): boolean {
    if (SileroTtsNative.isLangModelPresent(iso)) {
      return true;
    }
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    return SileroModelInstaller.fileSize(SileroModelPaths.modelFilePath(root, iso)) >= MIN_MODEL_BYTES;
  }

  static hasVoiceAssets(iso: string, filesDir?: string): boolean {
    const code = iso.trim().toLowerCase();
    if (SileroModelPaths.usesSummerTtsIso(code)) {
      return SileroModelInstaller.hasSummerZhModel(filesDir);
    }
    if (SileroModelPaths.usesPiperPlusIso(code)) {
      return SileroModelInstaller.hasPiperJaBundle(filesDir);
    }
    if (SileroModelPaths.usesPiperIso(code) && !SileroModelPaths.usesPiperPlusIso(code)) {
      return SileroModelInstaller.hasPiperLangBundle(code, filesDir);
    }
    if (SileroModelPaths.usesRhvoiceIso(code)) {
      return SileroModelInstaller.hasRhvoiceVoiceForIso(code, filesDir);
    }
    return false;
  }

  static hasRhvoiceVoiceForIso(iso: string, filesDir?: string): boolean {
    const code = iso.trim().toLowerCase();
    if (!SileroModelPaths.usesRhvoiceIso(code)) {
      return false;
    }
    if (SileroTtsNative.isLangModelPresent(code)) {
      return true;
    }
    const profile = TtsVoiceCatalog.rhvoiceProfileForIso(code);
    const langDir = SileroModelPaths.rhvoiceLangDirForIso(code);
    if (profile.length === 0 || langDir.length === 0) {
      return false;
    }
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    const dataRoot = SileroModelPaths.rhvoiceDataRoot(root);
    const voiceInfo = `${dataRoot}/voices/${profile}/voice.info`;
    if (SileroModelInstaller.fileSize(voiceInfo) < 16) {
      return false;
    }
    const langInfo = `${dataRoot}/languages/${langDir}/language.info`;
    if (SileroModelInstaller.fileSize(langInfo) < 16) {
      return false;
    }
    const graphTxt = `${dataRoot}/languages/${langDir}/graph.txt`;
    if (SileroModelInstaller.fileSize(graphTxt) >= 64) {
      return true;
    }
    const tokFst = `${dataRoot}/languages/${langDir}/tok.fst`;
    if (SileroModelInstaller.fileSize(tokFst) < 1000) {
      return false;
    }
    const g2pFst = `${dataRoot}/languages/${langDir}/g2p.fst`;
    if (SileroModelInstaller.fileSize(g2pFst) >= 64) {
      return true;
    }
    const cmulexFst = `${dataRoot}/languages/${langDir}/cmulex.fst`;
    return SileroModelInstaller.fileSize(cmulexFst) >= 1000;
  }

  /** piper-plus FIXED_PUA_MAPPING — 与 scripts/sanitize_piperplus_ja_config.py 一致 */
  private static readonly PIPER_JA_PUA_PHONEME_FIX: Record<string, string> = {
    'ɔɪ': '\uE062',
    'œ̃': '\uE063',
    'ɐ̃': '\uE064',
  };

  /** 解压后修正旧版 config（多码点 phoneme_id_map 会导致 piper 创建失败） */
  private static sanitizePiperJaConfigAtRoot(modelRoot: string): boolean {
    const cfgPath = SileroModelPaths.piperJaConfigPath(modelRoot);
    try {
      const buf = fileIo.readTextSync(cfgPath);
      const cfg = JSON.parse(buf) as Record<string, Object>;
      const pidMap = cfg['phoneme_id_map'] as Record<string, Object> | undefined;
      if (pidMap === undefined) {
        return false;
      }
      let changed = false;
      const keys = Object.keys(pidMap);
      const newMap: Record<string, Object> = {};
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const pua = SileroModelInstaller.PIPER_JA_PUA_PHONEME_FIX[key];
        if (pua !== undefined) {
          newMap[pua] = pidMap[key];
          changed = true;
        } else {
          newMap[key] = pidMap[key];
        }
      }
      if (changed) {
        cfg['phoneme_id_map'] = newMap;
        SileroModelInstaller.writeUtf8TextFile(cfgPath, JSON.stringify(cfg));
        hilog.warn(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja config sanitized (PUA phoneme_id_map)');
      }
      return SileroModelInstaller.piperJaPhonemeIdMapIsCppCompatible(modelRoot);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'piper ja sanitize failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 部分 Piper 模型（如 is_IS-salka）缺 phoneme_type，piper 会误用 MultilingualPhonemes，
   * 导致只合成约 0.2s 杂音。若 config 含 espeak.voice 则补 phoneme_type=espeak。
   */
  static sanitizePiperLangEspeakConfig(modelRoot: string, iso: string): boolean {
    const code = iso.trim().toLowerCase();
    if (code.length === 0 || SileroModelPaths.usesPiperPlusIso(code)) {
      return false;
    }
    const cfgPath = SileroModelPaths.piperConfigPath(modelRoot, code);
    if (cfgPath.length === 0) {
      return false;
    }
    try {
      const buf = fileIo.readTextSync(cfgPath);
      const cfg = JSON.parse(buf) as Record<string, Object>;
      const existing = cfg['phoneme_type'];
      if (typeof existing === 'string' && existing.length > 0) {
        return false;
      }
      const espeak = cfg['espeak'] as Record<string, Object> | undefined;
      const voice = espeak !== undefined ? espeak['voice'] : undefined;
      if (typeof voice !== 'string' || voice.length === 0) {
        return false;
      }
      cfg['phoneme_type'] = 'espeak';
      SileroModelInstaller.writeUtf8TextFile(cfgPath, JSON.stringify(cfg));
      hilog.warn(DOMAIN, TAG, 'piper %{public}s config patched phoneme_type=espeak', code);
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'piper %{public}s config sanitize failed: %{public}s', code, JSON.stringify(e));
      return false;
    }
  }

  /**
   * piper-plus 日语包使用 config.json；旧版 native 合成时查找 <onnx>.json。
   * 将 config 同步为 onnx.json 别名，避免「Piper config missing: …onnx.json」。
   */
  private static ensurePiperJaOnnxJsonAlias(modelRoot: string): void {
    const cfgPath = SileroModelPaths.piperJaConfigPath(modelRoot);
    const aliasPath = SileroModelPaths.piperJaOnnxJsonPath(modelRoot);
    const cfgSize = SileroModelInstaller.fileSize(cfgPath);
    if (cfgSize < 256) {
      return;
    }
    const aliasSize = SileroModelInstaller.fileSize(aliasPath);
    if (aliasSize >= cfgSize) {
      return;
    }
    try {
      const text = fileIo.readTextSync(cfgPath);
      SileroModelInstaller.writeUtf8TextFile(aliasPath, text);
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja wrote onnx.json alias from config.json');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'piper ja onnx.json alias failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 已安装语音包若缺 phoneme_type，朗读前修补一次并释放 Piper 缓存 */
  static ensurePiperLangConfigReady(filesDir: string, iso: string): void {
    if (filesDir.length === 0) {
      return;
    }
    const code = iso.trim().toLowerCase();
    const modelRoot = SileroModelPaths.modelRoot(filesDir);
    if (SileroModelPaths.usesPiperPlusIso(code)) {
      SileroModelInstaller.sanitizePiperJaConfigAtRoot(modelRoot);
      SileroModelInstaller.ensurePiperJaOnnxJsonAlias(modelRoot);
      return;
    }
    if (!SileroModelPaths.usesPiperIso(code)) {
      return;
    }
    if (SileroModelInstaller.sanitizePiperLangEspeakConfig(modelRoot, code)) {
      SileroTtsNative.cancelSynthesis();
    }
  }

  private static logPiperJaBundleCheck(modelRoot: string): void {
    const onnx = SileroModelInstaller.fileSize(SileroModelPaths.piperJaOnnxPath(modelRoot));
    const cfg = SileroModelInstaller.fileSize(SileroModelPaths.piperJaConfigPath(modelRoot));
    const dict = SileroModelPaths.piperJaDictDir(modelRoot);
    const sysDic = SileroModelInstaller.fileSize(`${dict}/sys.dic`);
    const unkDic = SileroModelInstaller.fileSize(`${dict}/unk.dic`);
    const mapOk = SileroModelInstaller.piperJaPhonemeIdMapIsCppCompatible(modelRoot);
    hilog.error(LOG_DOMAIN_UI, LOG_TAG_UI,
      'piper ja bundle invalid onnx=%{public}d cfg=%{public}d sys.dic=%{public}d unk.dic=%{public}d mapOk=%{public}s root=%{public}s',
      onnx, cfg, sysDic, unkDic, String(mapOk), SileroModelPaths.piperJaBundleDir(modelRoot));
  }

  /** piper.cpp requires every phoneme_id_map key to be a single Unicode codepoint. */
  private static piperJaPhonemeIdMapIsCppCompatible(modelRoot: string): boolean {
    const cfgPath = SileroModelPaths.piperJaConfigPath(modelRoot);
    try {
      const buf = fileIo.readTextSync(cfgPath);
      const cfg = JSON.parse(buf) as Record<string, Object>;
      const pidMap = cfg['phoneme_id_map'] as Record<string, Object> | undefined;
      if (pidMap === undefined) {
        return false;
      }
      for (const key of Object.keys(pidMap)) {
        if (key.length > 1) {
          return false;
        }
      }
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'piper ja config check failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  static hasPiperJaBundle(filesDir?: string): boolean {
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    const onnxOk = SileroModelInstaller.fileSize(SileroModelPaths.piperJaOnnxPath(root)) >= MIN_MODEL_BYTES;
    const cfgOk = SileroModelInstaller.fileSize(SileroModelPaths.piperJaConfigPath(root)) >= 1024;
    const cfgMapOk = cfgOk && SileroModelInstaller.piperJaPhonemeIdMapIsCppCompatible(root);
    const dictDir = SileroModelPaths.piperJaDictDir(root);
    const dictOk = SileroModelInstaller.fileSize(`${dictDir}/sys.dic`) >= PIPER_JA_SYS_DIC_MIN_BYTES &&
      SileroModelInstaller.fileSize(`${dictDir}/unk.dic`) >= PIPER_JA_UNK_DIC_MIN_BYTES;
    if (onnxOk && cfgMapOk && dictOk) {
      return true;
    }
    const altDict = `${SileroModelPaths.piperJaBundleDir(root)}/open_jtalk_dic_utf_8-1.11`;
    const altOk = SileroModelInstaller.fileSize(`${altDict}/sys.dic`) >= PIPER_JA_SYS_DIC_MIN_BYTES &&
      SileroModelInstaller.fileSize(`${altDict}/unk.dic`) >= PIPER_JA_UNK_DIC_MIN_BYTES;
    return onnxOk && cfgMapOk && altOk;
  }

  static hasEspeakData(filesDir?: string): boolean {
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    return SileroModelInstaller.fileSize(SileroModelPaths.espeakMarkerPath(root)) >= ESPEAK_MARKER_MIN_BYTES;
  }

  static hasPiperLangBundle(iso: string, filesDir?: string): boolean {
    const code = iso.trim().toLowerCase();
    if (!SileroModelPaths.usesPiperIso(code) || SileroModelPaths.usesPiperPlusIso(code)) {
      return false;
    }
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    const onnxOk = SileroModelInstaller.fileSize(SileroModelPaths.piperOnnxPath(root, code)) >= MIN_MODEL_BYTES;
    const cfgOk = SileroModelInstaller.fileSize(SileroModelPaths.piperConfigPath(root, code)) >= 256;
    return onnxOk && cfgOk && SileroModelInstaller.hasEspeakData(filesDir);
  }

  static pruneIncompleteSummerZhModel(filesDir?: string): void {
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return;
    }
    const path = SileroModelPaths.summerZhModelPath(root);
    const sz = SileroModelInstaller.fileSize(path);
    if (sz > 0 && sz < SileroModelPaths.SUMMER_ZH_MIN_BYTES) {
      hilog.warn(DOMAIN, TAG, 'remove incomplete zh model bytes=%{public}d', sz);
      SileroModelInstaller.removePathQuiet(path);
      SileroModelInstaller.removePathQuiet(`${path}.part`);
    }
  }

  static hasSummerZhModel(filesDir?: string): boolean {
    SileroModelInstaller.pruneIncompleteSummerZhModel(filesDir);
    const root = filesDir !== undefined && filesDir.length > 0
      ? SileroModelPaths.modelRoot(filesDir)
      : SileroTtsNative.getModelRoot();
    if (root.length === 0) {
      return false;
    }
    return SileroModelInstaller.fileSize(SileroModelPaths.summerZhModelPath(root)) >=
      SileroModelPaths.SUMMER_ZH_MIN_BYTES;
  }

  static isInstallInProgress(): boolean {
    return SileroModelInstaller.installLock;
  }

  /** 朗读前等待后台 rawfile 拷贝结束，避免加载半成品模型导致 native SIGSEGV */
  static async waitForInstallIdle(maxWaitMs: number = 120000): Promise<void> {
    const stepMs = 80;
    let waited = 0;
    while (SileroModelInstaller.installLock && waited < maxWaitMs) {
      await new Promise<void>((resolve) => setTimeout(resolve, stepMs));
      waited += stepMs;
    }
  }

  static hasMobileInferenceModel(iso: string, filesDir?: string): boolean {
    const code = iso.trim().toLowerCase();
    if (SileroModelPaths.usesSummerTtsIso(code)) {
      if (SileroTtsNative.isLangModelPresent(code)) {
        return true;
      }
      return SileroModelInstaller.hasSummerZhModel(filesDir);
    }
    if (SileroModelPaths.usesPiperPlusIso(code)) {
      if (filesDir !== undefined && filesDir.length > 0) {
        SileroTtsNative.syncModelRoot(filesDir);
      }
      const diskOk = (filesDir !== undefined && filesDir.length > 0)
        ? SileroModelInstaller.hasPiperJaBundle(filesDir)
        : false;
      const nativeOk = SileroTtsNative.isLangModelPresent(code);
      return diskOk && nativeOk;
    }
    if (SileroModelPaths.usesPiperIso(code) && !SileroModelPaths.usesPiperPlusIso(code)) {
      if (filesDir !== undefined && filesDir.length > 0) {
        SileroTtsNative.syncModelRoot(filesDir);
      }
      const diskOk = (filesDir !== undefined && filesDir.length > 0)
        ? SileroModelInstaller.hasPiperLangBundle(code, filesDir)
        : false;
      const nativeOk = SileroTtsNative.isLangModelPresent(code);
      return diskOk && nativeOk;
    }
    if (SileroModelPaths.usesRhvoiceIso(code)) {
      if (filesDir !== undefined && filesDir.length > 0) {
        SileroTtsNative.syncModelRoot(filesDir);
      }
      const diskOk = (filesDir !== undefined && filesDir.length > 0)
        ? SileroModelInstaller.hasRhvoiceVoiceForIso(code, filesDir)
        : false;
      if (!SileroTtsNative.usesRhvoice()) {
        return diskOk;
      }
      return diskOk && SileroTtsNative.isLangModelPresent(code);
    }
    return false;
  }

  static canOpenRawMobileForIso(context: common.Context, iso: string): boolean {
    const candidates = SileroModelPaths.rawMobileFileCandidatesForIso(iso);
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  private static destPathForIso(iso: string, filesDir: string): string {
    return SileroModelPaths.modelFilePath(SileroModelPaths.modelRoot(filesDir), iso);
  }

  private static fileSize(path: string): number {
    if (path.length === 0) {
      return 0;
    }
    try {
      const st = fileIo.statSync(path);
      return st.size;
    } catch (_e) {
      return 0;
    }
  }

  private static writeUtf8TextFile(path: string, content: string): void {
    const bytes = new util.TextEncoder().encodeInto(content);
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, bytes.buffer, { offset: bytes.byteOffset, length: bytes.byteLength });
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static pathExists(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    try {
      fileIo.accessSync(path);
      return true;
    } catch (_e) {
      return false;
    }
  }

  private static zipLooksValid(path: string, minBytes: number = MIN_MODEL_BYTES): boolean {
    if (SileroModelInstaller.fileSize(path) < minBytes) {
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

  private static async decompressZipToModelRoot(zipPath: string, modelRoot: string): Promise<void> {
    SileroModelInstaller.ensureModelDir(modelRoot);
    await zlib.decompressFile(zipPath, modelRoot, {});
  }

  static hasAnyModel(): boolean {
    for (let i = 0; i < SileroModelPaths.SUPPORTED_ISOS.length; i++) {
      if (SileroModelInstaller.hasLangModel(SileroModelPaths.SUPPORTED_ISOS[i])) {
        return true;
      }
    }
    return false;
  }

  /** 能否从 HAP rawfile 打开该语种模型（比 getRawFileList 更可靠） */
  static canOpenRawForIso(context: common.Context, iso: string): boolean {
    const candidates = SileroModelPaths.rawFileCandidatesForIso(iso);
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  static async isRawBundledForIso(context: common.Context, iso: string): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    if (SileroModelPaths.usesPiperPlusIso(code) && SileroModelInstaller.isPiperJaBundledInHap(context)) {
      return true;
    }
    if (SileroModelPaths.usesPiperIso(code) && !SileroModelPaths.usesPiperPlusIso(code) &&
      SileroModelInstaller.isPiperLangBundledInHap(context, code)) {
      return true;
    }
    if (SileroModelPaths.usesRhvoiceIso(code) && SileroModelInstaller.isRhvoiceBundledInHap(context)) {
      return true;
    }
    return SileroModelInstaller.canOpenRawForIso(context, iso);
  }

  static resolveBundledRhvoiceZipPath(context: common.Context): string {
    const zipName = SileroModelPaths.RHVOICE_RAW_ZIP;
    const candidates = SileroModelPaths.bundledResfileZipCandidates(context.resourceDir ?? '', zipName);
    for (let i = 0; i < candidates.length; i++) {
      if (SileroModelInstaller.fileSize(candidates[i]) >= RHVOICE_ZIP_MIN_BYTES) {
        return candidates[i];
      }
    }
    return '';
  }

  static isRhvoiceBundledInHap(context: common.Context): boolean {
    if (SileroModelInstaller.resolveBundledRhvoiceZipPath(context).length > 0) {
      return true;
    }
    return SileroModelInstaller.canOpenRawRhvoiceZip(context);
  }

  static canOpenRawRhvoiceZip(context: common.Context): boolean {
    const candidates = SileroModelPaths.rhvoiceRawZipCandidates();
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  static canOpenRawPiperJaZip(context: common.Context): boolean {
    const candidates = SileroModelPaths.piperJaRawZipCandidates();
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  /** 在 resourceDir 下探测打包的 piper 日语 zip（含 resfile 子路径） */
  static resolveBundledPiperJaZipPath(context: common.Context): string {
    const zipName = SileroModelPaths.PIPER_JA_RAW_ZIP;
    const candidates = SileroModelPaths.bundledResfileZipCandidates(context.resourceDir ?? '', zipName);
    for (let i = 0; i < candidates.length; i++) {
      const p = candidates[i];
      if (SileroModelInstaller.pathExists(p) && SileroModelInstaller.zipLooksValid(p, PIPER_JA_ZIP_MIN_BYTES)) {
        return p;
      }
    }
    return '';
  }

  /** 日语 zip 在 resfile（优先）或 rawfile */
  static isPiperJaBundledInHap(context: common.Context): boolean {
    if (SileroModelInstaller.resolveBundledPiperJaZipPath(context).length > 0) {
      return true;
    }
    return SileroModelInstaller.canOpenRawPiperJaZip(context);
  }

  static canOpenRawPiperLangZip(context: common.Context, iso: string): boolean {
    const candidates = SileroModelPaths.piperRawZipCandidates(iso);
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  static canOpenRawEspeakZip(context: common.Context): boolean {
    const candidates = SileroModelPaths.espeakRawZipCandidates();
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  static resolveBundledEspeakZipPath(context: common.Context): string {
    const zipName = SileroModelPaths.ESPEAK_RAW_ZIP;
    const candidates = SileroModelPaths.bundledResfileZipCandidates(context.resourceDir ?? '', zipName);
    for (let i = 0; i < candidates.length; i++) {
      const p = candidates[i];
      if (SileroModelInstaller.pathExists(p) && SileroModelInstaller.zipLooksValid(p, ESPEAK_ZIP_MIN_BYTES)) {
        return p;
      }
    }
    return '';
  }

  static isEspeakBundledInHap(context: common.Context): boolean {
    if (SileroModelInstaller.resolveBundledEspeakZipPath(context).length > 0) {
      return true;
    }
    return SileroModelInstaller.canOpenRawEspeakZip(context);
  }

  static resolveBundledPiperLangZipPath(context: common.Context, iso: string): string {
    const zipName = SileroModelPaths.piperRawZipName(iso);
    const candidates = SileroModelPaths.bundledResfileZipCandidates(context.resourceDir ?? '', zipName);
    for (let i = 0; i < candidates.length; i++) {
      if (SileroModelInstaller.fileSize(candidates[i]) >= MIN_MODEL_BYTES) {
        return candidates[i];
      }
    }
    return '';
  }

  static isPiperLangBundledInHap(context: common.Context, iso: string): boolean {
    if (SileroModelInstaller.resolveBundledPiperLangZipPath(context, iso).length > 0) {
      return true;
    }
    return SileroModelInstaller.canOpenRawPiperLangZip(context, iso);
  }

  private static resolveRawName(context: common.Context, iso: string): string {
    const candidates = SileroModelPaths.rawFileCandidatesForIso(iso);
    const rm = context.resourceManager;
    for (let i = 0; i < candidates.length; i++) {
      try {
        rm.getRawFdSync(candidates[i]);
        rm.closeRawFdSync(candidates[i]);
        return candidates[i];
      } catch (_e) {
      }
    }
    return '';
  }

  static installLangIfNeeded(
    context: common.Context,
    iso: string,
    onProgress: (percent: number) => void,
    onDone: (ok: boolean) => void,
  ): void {
    const code = iso.trim().toLowerCase();
    SileroModelInstaller.lastFailure = SileroInstallFailure.NONE;
    SileroModelInstaller.lastFailureDetail = '';
    if (!SileroModelPaths.isSupportedIso(code)) {
      SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED, 'unsupported iso');
      onDone(false);
      return;
    }
    if (SileroModelInstaller.hasVoiceAssets(code, context.filesDir)) {
      onProgress(100);
      onDone(true);
      return;
    }
    if (SileroModelPaths.usesPiperPlusIso(code)) {
      SileroModelInstaller.installLock = true;
      const jaTask = async (): Promise<boolean> => {
        try {
          return await SileroModelInstaller.installPiperJaBundle(context, onProgress);
        } catch (e) {
          SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
            `piper ja exception: ${JSON.stringify(e)}`);
          return false;
        } finally {
          SileroModelInstaller.installLock = false;
        }
      };
      jaTask().then((ok: boolean) => {
        onProgress(ok ? 100 : 0);
        onDone(ok);
      }).catch((e: Object) => {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          `piper ja task: ${JSON.stringify(e)}`);
        onProgress(0);
        onDone(false);
      });
      return;
    }
    if (SileroModelPaths.usesPiperIso(code) && !SileroModelPaths.usesPiperPlusIso(code)) {
      SileroModelInstaller.installLock = true;
      const piperTask = async (): Promise<boolean> => {
        try {
          return await SileroModelInstaller.installPiperLangBundle(context, code, onProgress);
        } catch (e) {
          SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
            `piper ${code} exception: ${JSON.stringify(e)}`);
          return false;
        } finally {
          SileroModelInstaller.installLock = false;
        }
      };
      piperTask().then((ok: boolean) => {
        onProgress(ok ? 100 : 0);
        onDone(ok);
      }).catch((e: Object) => {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          `piper ${code} task: ${JSON.stringify(e)}`);
        onProgress(0);
        onDone(false);
      });
      return;
    }
    if (SileroModelPaths.usesRhvoiceIso(code)) {
      SileroModelInstaller.lastFailure = SileroInstallFailure.NOT_BUNDLED;
      onDone(false);
      return;
    }
    if (SileroModelPaths.usesSummerTtsIso(code)) {
      SileroModelInstaller.installLock = true;
      const zhTask = async (): Promise<boolean> => {
        try {
          const destPath = SileroModelInstaller.destPathForIso(code, context.filesDir);
          if (destPath.length === 0) {
            SileroModelInstaller.lastFailure = SileroInstallFailure.COPY_FAILED;
            return false;
          }
          if (SileroModelInstaller.hasSummerZhModel(context.filesDir)) {
            return true;
          }
          onProgress(2);
          if (!SileroModelInstaller.canOpenRawForIso(context, code)) {
            SileroModelInstaller.lastFailure = SileroInstallFailure.NOT_BUNDLED;
            return false;
          }
          const rawName = SileroModelInstaller.resolveRawName(context, code);
          if (rawName.length === 0) {
            SileroModelInstaller.lastFailure = SileroInstallFailure.NOT_BUNDLED;
            return false;
          }
          const copied = await SileroModelInstaller.copyRawFileChunked(context, rawName, destPath, onProgress,
            SileroModelPaths.SUMMER_ZH_MIN_BYTES, true);
          if (!copied) {
            SileroModelInstaller.lastFailure = SileroInstallFailure.COPY_FAILED;
            SileroModelInstaller.removePathQuiet(destPath);
          }
          return copied && SileroModelInstaller.hasSummerZhModel(context.filesDir);
        } finally {
          SileroModelInstaller.installLock = false;
        }
      };
      zhTask().then((ok: boolean) => {
        onProgress(ok ? 100 : 0);
        onDone(ok);
      });
      return;
    }
    if (SileroModelInstaller.installLock) {
      SileroModelInstaller.lastFailure = SileroInstallFailure.BUSY;
      onDone(false);
      return;
    }
    SileroModelInstaller.lastFailure = SileroInstallFailure.COPY_FAILED;
    onDone(false);
  }

  private static ensureModelDir(modelRoot: string): void {
    try {
      fileIo.mkdirSync(modelRoot, true);
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
        const children = fileIo.listFileSync(path);
        for (let i = 0; i < children.length; i++) {
          SileroModelInstaller.removePathQuiet(`${path}/${children[i]}`);
        }
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (_e) {
    }
  }

  /** 清除不完整日语包，便于设置页重新安装 */
  static clearPiperJaVoiceCache(filesDir: string): void {
    SileroModelInstaller.clearPiperJaInstall(filesDir);
  }

  private static clearPiperJaInstall(filesDir: string): void {
    const modelRoot = SileroModelPaths.modelRoot(filesDir);
    const zipPath = `${modelRoot}/${SileroModelPaths.PIPER_JA_RAW_ZIP}`;
    SileroModelInstaller.removePathQuiet(SileroModelPaths.piperJaBundleDir(modelRoot));
    SileroModelInstaller.removePathQuiet(zipPath);
    hilog.warn(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper-plus ja install cache cleared under %{public}s', modelRoot);
  }

  private static async installPiperJaBundle(
    context: common.Context,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const modelRoot = SileroModelPaths.modelRoot(context.filesDir);
    const bundledZip = SileroModelInstaller.resolveBundledPiperJaZipPath(context);
    hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI,
      'piper ja install start root=%{public}s resourceDir=%{public}s bundledZip=%{public}s',
      modelRoot, context.resourceDir ?? '', bundledZip);
    if (SileroModelInstaller.hasPiperJaBundle(context.filesDir)) {
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja bundle already present');
      return true;
    }
    SileroModelInstaller.clearPiperJaInstall(context.filesDir);
    SileroModelInstaller.ensureModelDir(modelRoot);
    const zipName = SileroModelPaths.PIPER_JA_RAW_ZIP;
    const zipPath = `${modelRoot}/${zipName}`;
    onProgress(3);

    let zipForDecompress = '';
    if (bundledZip.length > 0) {
      zipForDecompress = bundledZip;
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja use bundled zip %{public}s size=%{public}d',
        bundledZip, SileroModelInstaller.fileSize(bundledZip));
    } else {
      let haveZip = false;
      const rawCandidates = SileroModelPaths.piperJaRawZipCandidates();
      SileroModelInstaller.removePathQuiet(zipPath);
      for (let i = 0; i < rawCandidates.length && !haveZip; i++) {
        if (!SileroModelInstaller.canOpenRawEntry(context, rawCandidates[i])) {
          continue;
        }
        haveZip = await SileroModelInstaller.copyRawFileChunked(context, rawCandidates[i], zipPath, onProgress,
          PIPER_JA_ZIP_MIN_BYTES);
      }
      if (!haveZip && SileroModelInstaller.zipLooksValid(zipPath, PIPER_JA_ZIP_MIN_BYTES)) {
        haveZip = true;
        hilog.warn(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja using cached sandbox zip');
      }
      const copiedSize = SileroModelInstaller.fileSize(zipPath);
      const valid = haveZip && SileroModelInstaller.zipLooksValid(zipPath, PIPER_JA_ZIP_MIN_BYTES);
      if (haveZip) {
        hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI,
          'piper ja copy raw/resfile ok=%{public}s valid=%{public}s size=%{public}d',
          String(haveZip), String(valid), copiedSize);
      }
      if (haveZip && !valid) {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          'bundled zip copy corrupt (bad PK header or size)');
        SileroModelInstaller.removePathQuiet(zipPath);
        return false;
      }
      if (!valid) {
        SileroModelInstaller.setFailure(SileroInstallFailure.NOT_BUNDLED,
          `${zipName} missing in HAP — run pack_piperplus_ja_rawfile.ps1 then Clean+Rebuild`);
        return false;
      }
      zipForDecompress = zipPath;
    }

    onProgress(96);
    try {
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja decompress %{public}s -> %{public}s',
        zipForDecompress, modelRoot);
      await SileroModelInstaller.decompressZipToModelRoot(zipForDecompress, modelRoot);
      SileroModelInstaller.sanitizePiperJaConfigAtRoot(modelRoot);
      SileroModelInstaller.ensurePiperJaOnnxJsonAlias(modelRoot);
      const ok = SileroModelInstaller.hasPiperJaBundle(context.filesDir);
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'piper ja unzip done bundleOk=%{public}s', String(ok));
      if (ok) {
        SileroTtsNative.syncModelRoot(context.filesDir);
      }
      if (!ok) {
        SileroModelInstaller.logPiperJaBundleCheck(modelRoot);
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          'unzip finished but ONNX/config/OpenJTalk incomplete — check sys.dic/unk.dic paths');
        SileroModelInstaller.clearPiperJaInstall(context.filesDir);
      }
      return ok;
    } catch (e) {
      const be = e as BusinessError;
      const msg = `decompress err ${be.code ?? -1}: ${be.message ?? JSON.stringify(e)}`;
      SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED, msg);
      SileroModelInstaller.clearPiperJaInstall(context.filesDir);
      return false;
    }
  }

  private static clearPiperLangInstall(filesDir: string, iso: string): void {
    const modelRoot = SileroModelPaths.modelRoot(filesDir);
    const code = iso.trim().toLowerCase();
    const zipPath = `${modelRoot}/${SileroModelPaths.piperRawZipName(code)}`;
    SileroModelInstaller.removePathQuiet(SileroModelPaths.piperLangDir(modelRoot, code));
    SileroModelInstaller.removePathQuiet(zipPath);
  }

  private static async installEspeakData(
    context: common.Context,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const modelRoot = SileroModelPaths.modelRoot(context.filesDir);
    if (SileroModelInstaller.hasEspeakData(context.filesDir)) {
      return true;
    }
    SileroModelInstaller.ensureModelDir(modelRoot);
    const zipName = SileroModelPaths.ESPEAK_RAW_ZIP;
    const zipPath = `${modelRoot}/${zipName}`;
    onProgress(1);

    let zipForDecompress = '';
    const bundledZip = SileroModelInstaller.resolveBundledEspeakZipPath(context);
    if (bundledZip.length > 0) {
      zipForDecompress = bundledZip;
    } else {
      let haveZip = false;
      const rawCandidates = SileroModelPaths.espeakRawZipCandidates();
      SileroModelInstaller.removePathQuiet(zipPath);
      for (let i = 0; i < rawCandidates.length && !haveZip; i++) {
        if (!SileroModelInstaller.canOpenRawEntry(context, rawCandidates[i])) {
          continue;
        }
        haveZip = await SileroModelInstaller.copyRawFileChunked(context, rawCandidates[i], zipPath, onProgress,
          ESPEAK_MARKER_MIN_BYTES);
      }
      if (!haveZip && SileroModelInstaller.zipLooksValid(zipPath, ESPEAK_ZIP_MIN_BYTES)) {
        haveZip = true;
      }
      if (!haveZip || !SileroModelInstaller.zipLooksValid(zipPath, ESPEAK_ZIP_MIN_BYTES)) {
        SileroModelInstaller.setFailure(SileroInstallFailure.NOT_BUNDLED,
          `${zipName} missing — run scripts\\pack_espeak_data.ps1 then Clean+Rebuild HAP`);
        return false;
      }
      zipForDecompress = zipPath;
    }

    onProgress(92);
    try {
      await SileroModelInstaller.decompressZipToModelRoot(zipForDecompress, modelRoot);
      const ok = SileroModelInstaller.hasEspeakData(context.filesDir);
      if (!ok) {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          'espeak-ng-data unzip incomplete — check en_dict');
        SileroModelInstaller.removePathQuiet(SileroModelPaths.espeakDataRoot(modelRoot));
      }
      return ok;
    } catch (e) {
      const be = e as BusinessError;
      SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
        `espeak decompress: ${be.message ?? JSON.stringify(e)}`);
      SileroModelInstaller.removePathQuiet(SileroModelPaths.espeakDataRoot(modelRoot));
      return false;
    }
  }

  private static async installRhvoiceBundle(
    context: common.Context,
    iso: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    if (SileroModelInstaller.hasRhvoiceVoiceForIso(code, context.filesDir)) {
      return true;
    }
    const modelRoot = SileroModelPaths.modelRoot(context.filesDir);
    const bundledZip = SileroModelInstaller.resolveBundledRhvoiceZipPath(context);
    const rhRoot = SileroModelPaths.rhvoiceDataRoot(modelRoot);
    SileroModelInstaller.ensureModelDir(modelRoot);
    const zipName = SileroModelPaths.RHVOICE_RAW_ZIP;
    const zipPath = `${modelRoot}/${zipName}`;
    onProgress(3);

    let zipForDecompress = '';
    if (bundledZip.length > 0) {
      zipForDecompress = bundledZip;
    } else {
      let haveZip = false;
      const rawCandidates = SileroModelPaths.rhvoiceRawZipCandidates();
      SileroModelInstaller.removePathQuiet(zipPath);
      for (let i = 0; i < rawCandidates.length && !haveZip; i++) {
        if (!SileroModelInstaller.canOpenRawEntry(context, rawCandidates[i])) {
          continue;
        }
        haveZip = await SileroModelInstaller.copyRawFileChunked(context, rawCandidates[i], zipPath, onProgress,
          RHVOICE_ZIP_MIN_BYTES);
      }
      if (!haveZip && SileroModelInstaller.zipLooksValid(zipPath)) {
        haveZip = true;
      }
      if (!haveZip || !SileroModelInstaller.zipLooksValid(zipPath)) {
        SileroModelInstaller.setFailure(SileroInstallFailure.NOT_BUNDLED,
          `${zipName} missing — run scripts\\setup_rhvoice_kyrgyz.ps1 then pack_rhvoice_voices.ps1`);
        return false;
      }
      zipForDecompress = zipPath;
    }

    onProgress(96);
    try {
      await SileroModelInstaller.decompressZipToModelRoot(zipForDecompress, rhRoot);
      const ok = SileroModelInstaller.hasRhvoiceVoiceForIso(code, context.filesDir);
      if (ok) {
        SileroTtsNative.syncModelRoot(context.filesDir);
      } else {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          `rhvoice ${code} unzip incomplete — check voices/ and languages/`);
        SileroModelInstaller.removePathQuiet(rhRoot);
      }
      return ok;
    } catch (e) {
      const be = e as BusinessError;
      SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
        `rhvoice ${code} decompress: ${be.message ?? JSON.stringify(e)}`);
      SileroModelInstaller.removePathQuiet(rhRoot);
      return false;
    }
  }

  private static async installPiperLangBundle(
    context: common.Context,
    iso: string,
    onProgress: (percent: number) => void,
  ): Promise<boolean> {
    const code = iso.trim().toLowerCase();
    const modelRoot = SileroModelPaths.modelRoot(context.filesDir);
    const bundledZip = SileroModelInstaller.resolveBundledPiperLangZipPath(context, code);
    if (SileroModelInstaller.hasPiperLangBundle(code, context.filesDir)) {
      return true;
    }
    if (!await SileroModelInstaller.installEspeakData(context, (p: number) => {
      onProgress(Math.floor(p * 0.15));
    })) {
      return false;
    }
    SileroModelInstaller.clearPiperLangInstall(context.filesDir, code);
    SileroModelInstaller.ensureModelDir(modelRoot);
    const zipName = SileroModelPaths.piperRawZipName(code);
    const zipPath = `${modelRoot}/${zipName}`;
    onProgress(3);

    let zipForDecompress = '';
    if (bundledZip.length > 0) {
      zipForDecompress = bundledZip;
    } else {
      let haveZip = false;
      const rawCandidates = SileroModelPaths.piperRawZipCandidates(code);
      SileroModelInstaller.removePathQuiet(zipPath);
      for (let i = 0; i < rawCandidates.length && !haveZip; i++) {
        if (!SileroModelInstaller.canOpenRawEntry(context, rawCandidates[i])) {
          continue;
        }
        haveZip = await SileroModelInstaller.copyRawFileChunked(context, rawCandidates[i], zipPath, onProgress,
          MIN_MODEL_BYTES);
      }
      if (!haveZip && SileroModelInstaller.zipLooksValid(zipPath)) {
        haveZip = true;
      }
      if (!haveZip || !SileroModelInstaller.zipLooksValid(zipPath)) {
        SileroModelInstaller.setFailure(SileroInstallFailure.NOT_BUNDLED,
          `${zipName} missing — run scripts\\setup_piper_voices.ps1 -Iso ${code} then pack_piper_voices.ps1`);
        return false;
      }
      zipForDecompress = zipPath;
    }

    onProgress(96);
    try {
      await SileroModelInstaller.decompressZipToModelRoot(zipForDecompress, modelRoot);
      SileroModelInstaller.sanitizePiperLangEspeakConfig(modelRoot, code);
      const ok = SileroModelInstaller.hasPiperLangBundle(code, context.filesDir);
      if (ok) {
        SileroTtsNative.syncModelRoot(context.filesDir);
      } else {
        SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
          `piper ${code} unzip incomplete — check ONNX and .onnx.json`);
        SileroModelInstaller.clearPiperLangInstall(context.filesDir, code);
      }
      return ok;
    } catch (e) {
      const be = e as BusinessError;
      SileroModelInstaller.setFailure(SileroInstallFailure.COPY_FAILED,
        `piper ${code} decompress: ${be.message ?? JSON.stringify(e)}`);
      SileroModelInstaller.clearPiperLangInstall(context.filesDir, code);
      return false;
    }
  }

  private static canOpenRawEntry(context: common.Context, rawPath: string): boolean {
    try {
      context.resourceManager.getRawFdSync(rawPath);
      context.resourceManager.closeRawFdSync(rawPath);
      return true;
    } catch (_e) {
      return false;
    }
  }

  private static async copyRawFileChunked(
    context: common.Context,
    rawName: string,
    destPath: string,
    onProgress: (percent: number) => void,
    minWritten: number = MIN_MODEL_BYTES,
    atomicCommit: boolean = false,
  ): Promise<boolean> {
    const rm = context.resourceManager;
    let rawFd: resourceManager.RawFileDescriptor | undefined = undefined;
    let destFile: fileIo.File | undefined = undefined;
    const writePath = atomicCommit ? `${destPath}.part` : destPath;
    try {
      rawFd = rm.getRawFdSync(rawName);
      const modelRoot = SileroModelPaths.modelRoot(context.filesDir);
      SileroModelInstaller.ensureModelDir(modelRoot);
      SileroModelInstaller.removePathQuiet(writePath);
      if (atomicCommit) {
        SileroModelInstaller.removePathQuiet(destPath);
      }
      destFile = fileIo.openSync(writePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const total = rawFd.length;
      if (total <= 0) {
        return false;
      }
      fileIo.lseek(rawFd.fd, rawFd.offset, fileIo.WhenceType.SEEK_SET);
      let remaining = total;
      let written = 0;
      const chunkBuf = new ArrayBuffer(CHUNK_BYTES);
      while (remaining > 0) {
        const want = Math.min(CHUNK_BYTES, remaining);
        const readLen = fileIo.readSync(rawFd.fd, chunkBuf, { length: want });
        if (readLen <= 0) {
          hilog.error(DOMAIN, TAG, 'read stalled at %{public}d/%{public}d', written, total);
          return false;
        }
        fileIo.writeSync(destFile.fd, chunkBuf, { length: readLen });
        written += readLen;
        remaining -= readLen;
        const pct = 5 + Math.floor((written * 90) / total);
        onProgress(Math.min(95, pct));
      }
      onProgress(98);
      if (written < minWritten) {
        return false;
      }
      if (destFile !== undefined) {
        fileIo.closeSync(destFile);
        destFile = undefined;
      }
      if (atomicCommit) {
        try {
          fileIo.renameSync(writePath, destPath);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'atomic rename failed %{public}s -> %{public}s err=%{public}s',
            writePath, destPath, JSON.stringify(e));
          SileroModelInstaller.removePathQuiet(writePath);
          return false;
        }
      }
      return true;
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'chunk copy failed raw=%{public}s code=%{public}d msg=%{public}s',
        rawName, be.code ?? -1, be.message ?? JSON.stringify(e));
      SileroModelInstaller.removePathQuiet(writePath);
      return false;
    } finally {
      if (destFile !== undefined) {
        try {
          fileIo.closeSync(destFile);
        } catch (_e) {
        }
      }
      try {
        rm.closeRawFdSync(rawName);
      } catch (_e) {
      }
    }
  }
}
