export interface NativeSynthesizeResult {
  ok: boolean;
  pcm: ArrayBuffer;
  sampleRate: number;
  error: string;
}

export const isSileroLinked: () => boolean;
export const isLangModelPresent: (modelRoot: string, langIso: string) => boolean;
export const isAnyModelPresent: (modelRoot: string) => boolean;
export const getBuildInfo: () => string;
export const usesSummerTts: () => boolean;
export const usesPiperPlus: () => boolean;
export const usesRhvoice: () => boolean;
export const synthesize: (langIso: string, text: string, modelRoot: string) => Promise<NativeSynthesizeResult>;
export const cancelSynthesis: () => void;
