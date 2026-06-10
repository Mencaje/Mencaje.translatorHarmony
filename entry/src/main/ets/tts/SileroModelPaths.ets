import { TtsVoiceCatalog } from './TtsVoiceCatalog';

function ttsIso(iso: string): string {
  return TtsVoiceCatalog.normalizeSpeakIso(iso);
}

/**
 * 离线 TTS 模型路径（应用私有目录 silero_tts/，历史目录名保留）。
 * zh=SummerTTS；ja=piper-plus；Piper 语种=silero_tts/piper/<iso>/。
 */
export class SileroModelPaths {
  static readonly ROOT_FOLDER_NAME: string = 'silero_tts';

  static readonly SUPPORTED_ISOS: string[] = TtsVoiceCatalog.supportedIsos();

  static readonly RHVOICE_ISOS: string[] = TtsVoiceCatalog.rhvoiceIsos();

  static readonly PIPER_ISOS: string[] = TtsVoiceCatalog.piperIsos();

  static readonly PIPER_SUBDIR: string = 'piper';
  static readonly PIPER_JA_BUNDLE_DIR: string = 'piper-plus-ja';
  static readonly PIPER_JA_ONNX_FILE: string = 'tsukuyomi-chan-6lang-fp16.onnx';
  static readonly PIPER_JA_CONFIG_FILE: string = 'config.json';
  static readonly PIPER_JA_DICT_DIR: string = 'open_jtalk_dic';
  static readonly PIPER_JA_RAW_ZIP: string = 'piperplus_ja_voice.zip';

  static readonly ESPEAK_DATA_DIR: string = 'espeak-ng-data';
  static readonly ESPEAK_RAW_ZIP: string = 'espeakdata.zip';
  static readonly ESPEAK_MARKER_FILE: string = 'en_dict';

  static readonly RHVOICE_SUBDIR: string = 'rhvoice';
  static readonly RHVOICE_RAW_ZIP: string = 'rhvoice_voices.zip';

  static readonly SUMMER_ZH_MODEL_FILE: string = 'single_speaker_fast.bin';
  static readonly SUMMER_ZH_RAW_FILE: string = 'summer_single_speaker_fast.bin';
  /** single_speaker_fast.bin 约 76MB；低于此视为未完成拷贝，禁止 TTS 加载 */
  static readonly SUMMER_ZH_MIN_BYTES: number = 75 * 1024 * 1024;

  static modelRoot(filesDir: string): string {
    const base = filesDir.endsWith('/') ? filesDir : `${filesDir}/`;
    return `${base}${SileroModelPaths.ROOT_FOLDER_NAME}`;
  }

  static usesSummerTtsIso(iso: string): boolean {
    return ttsIso(iso) === 'zh';
  }

  static usesPiperPlusIso(iso: string): boolean {
    return ttsIso(iso) === 'ja';
  }

  /** 日语走 piper-plus-ja；其余 Piper 语种走 silero_tts/piper/<iso>/ */
  static usesPiperIso(iso: string): boolean {
    const code = ttsIso(iso);
    for (let i = 0; i < SileroModelPaths.PIPER_ISOS.length; i++) {
      if (SileroModelPaths.PIPER_ISOS[i] === code) {
        return true;
      }
    }
    return false;
  }

  static usesRhvoiceIso(iso: string): boolean {
    const code = ttsIso(iso);
    for (let i = 0; i < SileroModelPaths.RHVOICE_ISOS.length; i++) {
      if (SileroModelPaths.RHVOICE_ISOS[i] === code) {
        return true;
      }
    }
    return false;
  }

  static piperJaBundleDir(modelRoot: string): string {
    const root = modelRoot.endsWith('/') ? modelRoot : `${modelRoot}/`;
    return `${root}${SileroModelPaths.PIPER_JA_BUNDLE_DIR}`;
  }

  static piperJaOnnxPath(modelRoot: string): string {
    return `${SileroModelPaths.piperJaBundleDir(modelRoot)}/${SileroModelPaths.PIPER_JA_ONNX_FILE}`;
  }

  static piperJaConfigPath(modelRoot: string): string {
    return `${SileroModelPaths.piperJaBundleDir(modelRoot)}/${SileroModelPaths.PIPER_JA_CONFIG_FILE}`;
  }

  /** native piper-plus 对日语曾查找 *.onnx.json；与 config.json 内容一致 */
  static piperJaOnnxJsonPath(modelRoot: string): string {
    return `${SileroModelPaths.piperJaOnnxPath(modelRoot)}.json`;
  }

  static piperJaDictDir(modelRoot: string): string {
    return `${SileroModelPaths.piperJaBundleDir(modelRoot)}/${SileroModelPaths.PIPER_JA_DICT_DIR}`;
  }

  static piperLangDir(modelRoot: string, iso: string): string {
    const root = modelRoot.endsWith('/') ? modelRoot : `${modelRoot}/`;
    return `${root}${SileroModelPaths.PIPER_SUBDIR}/${ttsIso(iso)}`;
  }

  static piperOnnxFileName(iso: string): string {
    const key = TtsVoiceCatalog.piperVoiceKeyForIso(iso);
    return key.length > 0 ? `${key}.onnx` : '';
  }

  static piperConfigFileName(iso: string): string {
    const key = TtsVoiceCatalog.piperVoiceKeyForIso(iso);
    return key.length > 0 ? `${key}.onnx.json` : '';
  }

  static piperOnnxPath(modelRoot: string, iso: string): string {
    const name = SileroModelPaths.piperOnnxFileName(iso);
    return name.length > 0 ? `${SileroModelPaths.piperLangDir(modelRoot, iso)}/${name}` : '';
  }

  static piperConfigPath(modelRoot: string, iso: string): string {
    const name = SileroModelPaths.piperConfigFileName(iso);
    return name.length > 0 ? `${SileroModelPaths.piperLangDir(modelRoot, iso)}/${name}` : '';
  }

  static espeakDataRoot(modelRoot: string): string {
    const root = modelRoot.endsWith('/') ? modelRoot : `${modelRoot}/`;
    return `${root}${SileroModelPaths.ESPEAK_DATA_DIR}`;
  }

  static espeakMarkerPath(modelRoot: string): string {
    return `${SileroModelPaths.espeakDataRoot(modelRoot)}/${SileroModelPaths.ESPEAK_MARKER_FILE}`;
  }

  static espeakRawZipCandidates(): string[] {
    const zipName = SileroModelPaths.ESPEAK_RAW_ZIP;
    return [zipName, `resfile/${zipName}`, `resources/resfile/${zipName}`];
  }

  static piperRawZipName(iso: string): string {
    return `piper_${ttsIso(iso)}_voice.zip`;
  }

  static piperRawZipCandidates(iso: string): string[] {
    const zipName = SileroModelPaths.piperRawZipName(iso);
    return [zipName, `resfile/${zipName}`, `resources/resfile/${zipName}`];
  }

  /** 真机上 resfile zip 可能落在 resourceDir 下多种子路径 */
  static bundledResfileZipCandidates(resourceDir: string, zipName: string): string[] {
    if (resourceDir === undefined || resourceDir === null || resourceDir.length === 0) {
      return [];
    }
    const base = resourceDir.endsWith('/') ? resourceDir : `${resourceDir}/`;
    const out: string[] = [];
    const push = (p: string): void => {
      if (p.length > 0 && !out.includes(p)) {
        out.push(p);
      }
    };
    push(`${base}${zipName}`);
    const lower = base.toLowerCase();
    const alreadyResfile = lower.endsWith('/resfile/') || lower.endsWith('/resfile');
    if (!alreadyResfile) {
      push(`${base}resfile/${zipName}`);
      push(`${base}resources/resfile/${zipName}`);
    }
    return out;
  }

  static piperJaRawZipCandidates(): string[] {
    const zipName = SileroModelPaths.PIPER_JA_RAW_ZIP;
    return [zipName, `resfile/${zipName}`, `resources/resfile/${zipName}`];
  }

  static rhvoiceDataRoot(modelRoot: string): string {
    const root = modelRoot.endsWith('/') ? modelRoot : `${modelRoot}/`;
    return `${root}${SileroModelPaths.RHVOICE_SUBDIR}`;
  }

  static rhvoiceRawZipCandidates(): string[] {
    const zipName = SileroModelPaths.RHVOICE_RAW_ZIP;
    return [zipName, `resfile/${zipName}`, `resources/resfile/${zipName}`];
  }

  /** RHVoice languages/ 子目录名（与 native silero_tts_rhvoice.cpp 一致） */
  static rhvoiceLangDirForIso(iso: string): string {
    const code = ttsIso(iso);
    if (code === 'ky') {
      return 'Kyrgyz';
    }
    if (code === 'mk') {
      return 'Macedonian';
    }
    if (code === 'sq') {
      return 'Albanian';
    }
    if (code === 'eo') {
      return 'Esperanto';
    }
    return '';
  }

  static summerZhModelPath(modelRoot: string): string {
    const root = modelRoot.endsWith('/') ? modelRoot : `${modelRoot}/`;
    return `${root}${SileroModelPaths.SUMMER_ZH_MODEL_FILE}`;
  }

  static langNeedsPytorchMobile(_iso: string): boolean {
    return false;
  }

  static modelFileName(_iso: string): string {
    return '';
  }

  static rawFileNameForIso(iso: string): string {
    if (SileroModelPaths.usesSummerTtsIso(iso)) {
      return SileroModelPaths.SUMMER_ZH_RAW_FILE;
    }
    return '';
  }

  static rawFileCandidatesForIso(iso: string): string[] {
    const prefixed = SileroModelPaths.rawFileNameForIso(iso);
    if (prefixed.length > 0) {
      return [prefixed];
    }
    return [];
  }

  static rawMobileFileNameForIso(_iso: string): string {
    return '';
  }

  static rawMobileFileCandidatesForIso(_iso: string): string[] {
    return [];
  }

  static modelFilePath(modelRoot: string, iso: string): string {
    if (SileroModelPaths.usesSummerTtsIso(iso)) {
      return SileroModelPaths.summerZhModelPath(modelRoot);
    }
    return '';
  }

  static isSupportedIso(iso: string): boolean {
    const code = ttsIso(iso);
    for (let i = 0; i < SileroModelPaths.SUPPORTED_ISOS.length; i++) {
      if (SileroModelPaths.SUPPORTED_ISOS[i] === code) {
        return true;
      }
    }
    return false;
  }

  static downloadUrlForIso(_iso: string): string {
    return '';
  }
}
