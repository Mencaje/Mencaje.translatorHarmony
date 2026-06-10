import { TranslateLanguageOption } from '../translation/TranslateLanguages';

/** 首页 / 键盘条：居中语言单选弹窗 */
@Component
export struct LanguagePickerOverlay {
  @Prop visible: boolean = false;
  @Prop title: string = '';
  @Prop choices: TranslateLanguageOption[] = [];
  @Prop selectedNllbCode: string = '';
  /** 勿写默认空函数，否则父组件传入的回调可能绑不上 */
  onPick?: (option: TranslateLanguageOption) => void;
  onDismiss?: () => void;

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.ui_scrim'))
          .onClick(() => {
            if (this.onDismiss) {
              this.onDismiss();
            }
          })

        Column() {
          Text(this.title)
            .fontSize(18)
            .fontColor($r('app.color.ui_text_primary'))
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 12 })

          List() {
            ForEach(this.choices, (item: TranslateLanguageOption) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(item.label)
                      .fontSize(16)
                      .fontColor($r('app.color.ui_text_primary'))
                    Text(item.nllbCode)
                      .fontSize(11)
                      .fontColor($r('app.color.ui_input_hint'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (item.nllbCode === this.selectedNllbCode) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(20)
                      .fontColor([$r('app.color.ui_text_primary')])
                  }
                }
                .width('100%')
                .padding({ left: 8, right: 8, top: 12, bottom: 12 })
              }
              .onClick(() => {
                if (this.onPick) {
                  this.onPick(item);
                }
              })
            }, (item: TranslateLanguageOption) => item.nllbCode)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          Button('取消')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.ui_text_primary'))
            .backgroundColor($r('app.color.ui_ime_lang_pill'))
            .margin({ top: 12 })
            .onClick(() => {
              if (this.onDismiss) {
                this.onDismiss();
              }
            })
        }
        .width('88%')
        .constraintSize({ maxHeight: '72%' })
        .padding(20)
        .backgroundColor($r('app.color.ui_dialog_bg'))
        .borderRadius(20)
        .clip(true)
        .onClick(() => {
        })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Default)
    }
  }
}
