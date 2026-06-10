import { TtsSpeakPhase, TtsSpeakUi } from '../tts/TtsSpeakUi';

/**
 * 朗读按钮：加载中显示系统 LoadingProgress；播放中图标变蓝；再点停止。
 * 长按进入「朗读语言」语音包页。
 */
@Component
export struct SpeakActionButton {
  @Prop symbol: Resource = $r('sys.symbol.speaker_wave_3');
  @Prop iconSize: number = 22;
  @Prop actionEnabled: boolean = true;
  /** 全局朗读 UI 槽位，如 input / primary / row_0 */
  @Prop slotId: string = '';
  onSpeak?: () => void;
  onOpenVoicePack?: () => void;
  @StorageLink(TtsSpeakUi.PHASE_KEY) speakPhase: number = TtsSpeakPhase.IDLE;
  @StorageLink(TtsSpeakUi.SLOT_KEY) speakActiveSlot: string = '';
  @State private longPressHandled: boolean = false;

  private isLoading(): boolean {
    return this.speakPhase === TtsSpeakPhase.LOADING && this.speakActiveSlot === this.slotId;
  }

  private isPlaying(): boolean {
    return this.speakPhase === TtsSpeakPhase.PLAYING && this.speakActiveSlot === this.slotId;
  }

  private iconColor(): ResourceColor {
    return this.isPlaying() ? $r('app.color.ui_link_blue') : $r('app.color.ui_text_primary');
  }

  private triggerSpeak(): void {
    if (!this.actionEnabled || !this.onSpeak) {
      return;
    }
    this.onSpeak();
  }

  build() {
    if (this.isLoading()) {
      Row() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.ui_text_primary'))
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.triggerSpeak();
      })
    } else {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize)
          .fontColor([this.iconColor()])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .enabled(this.actionEnabled)
      .gesture(
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.actionEnabled && this.onOpenVoicePack) {
              this.longPressHandled = true;
              this.onOpenVoicePack();
            }
          })
      )
      .onClick(() => {
        if (this.longPressHandled) {
          this.longPressHandled = false;
          return;
        }
        this.triggerSpeak();
      })
    }
  }
}
