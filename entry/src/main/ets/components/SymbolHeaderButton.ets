/**
 * 顶栏图标按钮：华为系统 SymbolGlyph，无背景。
 */
@Component
export struct SymbolHeaderButton {
  @Prop symbol: Resource = $r('sys.symbol.gearshape');
  @Prop iconSize: number = 22;
  onAction?: () => void;

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.ui_text_primary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width(48)
    .height(48)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.onAction) {
        this.onAction();
      }
    })
  }
}
