import { router } from '@kit.ArkUI';
import { SymbolHeaderButton } from './SymbolHeaderButton';

/** 设置子页顶栏：与 TtsVoicePack（朗读语言）返回键位置、标题样式一致 */
@Component
export struct SettingsSubpageHeader {
  @Prop title: ResourceStr = '';
  @Prop topInsetVp: number = 0;

  build() {
    Column() {
      Row() {
        SymbolHeaderButton({
          symbol: $r('sys.symbol.chevron_left'),
          iconSize: 24,
          onAction: () => router.back()
        })
      }
      .width('100%')
      .padding({ left: 4, right: 8, top: this.topInsetVp + 4 })

      Text(this.title)
        .fontSize(18)
        .fontColor($r('app.color.ui_text_primary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: -40, bottom: 20 })
    }
    .width('100%')
  }
}
