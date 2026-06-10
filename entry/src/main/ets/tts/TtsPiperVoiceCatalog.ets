/**
 * Piper / piper-plus 官方预训练语音（rhasspy/piper-voices v1.0.0）。
 * 与 core 已支持 Piper 语种不重复；日语 ja 不在此表（走 piper-plus-ja）。
 * Piper 扩展：ar、ca、cs（见 ENTRIES；其余 Piper 语种已并入 core；pl 在 core）。
 */
export interface TtsPiperVoiceEntry {
  iso: string;
  label: string;
  /** HuggingFace 模型文件名前缀，如 de_DE-thorsten-medium */
  voiceKey: string;
}

export class TtsPiperVoiceCatalog {
  /** Piper 扩展语种；与 TtsVoiceCatalog 中 engine=piper 且 iso≠ja 且不在 core 一致 */
  static readonly ENTRIES: TtsPiperVoiceEntry[] = [
    { iso: 'ar', label: '阿拉伯语', voiceKey: 'ar_JO-kareem-medium' },
    { iso: 'ca', label: '加泰罗尼亚语', voiceKey: 'ca_ES-upc_ona-medium' },
    { iso: 'cs', label: '捷克语', voiceKey: 'cs_CZ-jirka-medium' },
  ];

  static findByIso(iso: string): TtsPiperVoiceEntry | undefined {
    const code = iso.trim().toLowerCase();
    for (let i = 0; i < TtsPiperVoiceCatalog.ENTRIES.length; i++) {
      if (TtsPiperVoiceCatalog.ENTRIES[i].iso === code) {
        return TtsPiperVoiceCatalog.ENTRIES[i];
      }
    }
    return undefined;
  }

  static voiceKeyForIso(iso: string): string {
    return TtsPiperVoiceCatalog.findByIso(iso)?.voiceKey ?? '';
  }
}
