import { hdsEffect } from '@kit.UIDesignKit';

/**
 * 底部操作按钮：系统 SymbolGlyph 图标 + HDS 沉浸光感（点光源 + 按压阴影）。
 */
@Component
export struct ImmersiveLightIconButton {
  @Prop symbol: Resource = $r('sys.symbol.gearshape');
  @Prop buttonSize: number = 52;
  @Prop iconSize: number = 22;
  onAction?: () => void;
  /** 长按回调（与 onAction 互斥触发，用于相机短按/长按） */
  onLongPress?: () => void;

  @State private lightType: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State private shadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

  private longPressTimer: number = -1;
  private longPressConsumed: boolean = false;

  private onTouchEvent(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.lightType = hdsEffect.PointLightSourceType.BRIGHT;
      this.shadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      if (this.onLongPress !== undefined) {
        this.longPressConsumed = false;
        this.longPressTimer = setTimeout(() => {
          this.longPressConsumed = true;
          this.onLongPress?.();
        }, 480);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.lightType = hdsEffect.PointLightSourceType.NONE;
      this.shadowType = hdsEffect.PressShadowType.NONE;
      if (this.longPressTimer >= 0) {
        clearTimeout(this.longPressTimer);
        this.longPressTimer = -1;
      }
    }
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.ui_text_primary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor($r('app.color.ui_home_action_surface'))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.lightType,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: Color.White,
          intensity: 0.75,
          height: 120
        }
      })
      .pressShadow(this.shadowType)
      .buildEffect())
    .onTouch((event: TouchEvent) => this.onTouchEvent(event))
    .onClick(() => {
      if (this.longPressConsumed) {
        this.longPressConsumed = false;
        return;
      }
      if (this.onAction) {
        this.onAction();
      }
    })
  }
}
