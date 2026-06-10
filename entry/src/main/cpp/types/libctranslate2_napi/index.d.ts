export interface NativeTranslateResult {
  text: string;
  error: string;
}

export interface NativeLoadModelResult {
  ok: boolean;
  error: string;
}

export const isCt2Linked: () => boolean;
export const isModelPresent: (modelDir: string) => boolean;
export const getBuildInfo: () => string;
export const loadModel: (modelDir: string) => Promise<NativeLoadModelResult>;
export const translate: (text: string, sourceNllb: string, targetNllb: string, modelDir: string) => Promise<NativeTranslateResult>;
