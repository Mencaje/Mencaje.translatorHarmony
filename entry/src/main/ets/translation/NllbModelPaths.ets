/**
 * NLLB-200 distilled 600M（CTranslate2 格式）本地模型路径。
 * 模型免费，需用户首次下载或从 PC 拷贝到应用私有目录（不随 HAP 打包，体积约 2GB+）。
 *
 * 转换命令（在 PC 上执行一次）：
 * pip install ctranslate2 transformers sentencepiece
 * ct2-transformers-converter --model facebook/nllb-200-distilled-600M --output_dir nllb-200-distilled-600M
 */
export class NllbModelPaths {
  static readonly MODEL_FOLDER_NAME: string = 'nllb-200-distilled-600M';

  static modelRoot(filesDir: string): string {
    const base = filesDir.endsWith('/') ? filesDir : `${filesDir}/`;
    return `${base}models/${NllbModelPaths.MODEL_FOLDER_NAME}`;
  }

  static bundledModelRoot(resourceDir: string): string {
    const candidates = NllbModelPaths.bundledModelDirCandidates(resourceDir);
    return candidates.length > 0 ? candidates[0] : '';
  }

  /** 真机上 resfile 可能落在 resourceDir 下多种子路径，需逐一探测 */
  static bundledModelDirCandidates(resourceDir: string): string[] {
    if (resourceDir === undefined || resourceDir === null || resourceDir.length === 0) {
      return [];
    }
    const base = resourceDir.endsWith('/') ? resourceDir : `${resourceDir}/`;
    const folder = NllbModelPaths.MODEL_FOLDER_NAME;
    const out: string[] = [];
    const push = (p: string): void => {
      if (p.length > 0 && !out.includes(p)) {
        out.push(p);
      }
    };
    push(`${base}${folder}`);
    const lower = base.toLowerCase();
    const alreadyResfile = lower.endsWith('/resfile/') || lower.endsWith('/resfile');
    if (!alreadyResfile) {
      push(`${base}resfile/${folder}`);
      push(`${base}resources/resfile/${folder}`);
    }
    return out;
  }

  static requiredFileNames(): string[] {
    return ['config.json', 'shared_vocabulary.json', 'sentencepiece.bpe.model'];
  }

  static hasWeightFile(modelDir: string): boolean {
    // 由 native 层做完整检测；ArkTS 侧仅作提示用
    return modelDir.length > 0;
  }
}
