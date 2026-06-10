/** 朗读按钮 UI：加载中转圈、播放中图标变蓝（全局仅一个活跃槽位） */
export enum TtsSpeakPhase {
  IDLE = 0,
  LOADING = 1,
  PLAYING = 2,
}

export class TtsSpeakUi {
  static readonly PHASE_KEY: string = 'ttsSpeakPhase';
  static readonly SLOT_KEY: string = 'ttsSpeakActiveSlot';

  static ensureStorage(): void {
    if (!AppStorage.has(TtsSpeakUi.PHASE_KEY)) {
      AppStorage.setOrCreate(TtsSpeakUi.PHASE_KEY, TtsSpeakPhase.IDLE);
    }
    if (!AppStorage.has(TtsSpeakUi.SLOT_KEY)) {
      AppStorage.setOrCreate(TtsSpeakUi.SLOT_KEY, '');
    }
  }

  static getPhase(): TtsSpeakPhase {
    return AppStorage.get<number>(TtsSpeakUi.PHASE_KEY) as TtsSpeakPhase;
  }

  static getActiveSlot(): string {
    return AppStorage.get<string>(TtsSpeakUi.SLOT_KEY) ?? '';
  }

  static isSlotActive(slotId: string): boolean {
    return TtsSpeakUi.getActiveSlot() === slotId;
  }

  static setLoading(slotId: string): void {
    AppStorage.setOrCreate(TtsSpeakUi.SLOT_KEY, slotId);
    AppStorage.setOrCreate(TtsSpeakUi.PHASE_KEY, TtsSpeakPhase.LOADING);
  }

  static setPlaying(slotId: string): void {
    AppStorage.setOrCreate(TtsSpeakUi.SLOT_KEY, slotId);
    AppStorage.setOrCreate(TtsSpeakUi.PHASE_KEY, TtsSpeakPhase.PLAYING);
  }

  static setIdle(): void {
    AppStorage.setOrCreate(TtsSpeakUi.PHASE_KEY, TtsSpeakPhase.IDLE);
    AppStorage.setOrCreate(TtsSpeakUi.SLOT_KEY, '');
  }
}
