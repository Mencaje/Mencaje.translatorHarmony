import { common } from '@kit.AbilityKit';
import { router, window } from '@kit.ArkUI';
import { SettingsSubpageHeader } from '../components/SettingsSubpageHeader';
import { BrowserOpener } from '../util/BrowserOpener';

const PAGE_H_MARGIN: number = 16;

@Entry
@Component
struct AboutApp {
  @State statusBarTopInsetVp: number = 0;

  private websiteUrl: string = '';
  private feedbackEmail: string = '';
  private developerName: string = '';

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.refreshSystemBarInsets(hostCtx);
    const rm = hostCtx.resourceManager;
    this.websiteUrl = rm.getStringSync($r('app.string.about_app_website_url').id);
    this.feedbackEmail = rm.getStringSync($r('app.string.about_app_feedback_email').id);
    this.developerName = rm.getStringSync($r('app.string.about_app_developer_name').id);
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    }).catch(() => {
      // ignore
    });
  }

  private openWebsite(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    BrowserOpener.openHttpUrl(ctx, this.websiteUrl);
  }

  private openEmail(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    BrowserOpener.openEmail(ctx, this.feedbackEmail);
  }

  @Builder
  FieldBlock(label: ResourceStr, value: string, onTap?: () => void) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.ui_input_hint'))
        .width('100%')
      Text(value)
        .fontSize(16)
        .fontColor($r('app.color.ui_text_primary'))
        .width('100%')
        .margin({ top: 6 })
        .onClick(() => {
          if (onTap) {
            onTap();
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 14 })
  }

  build() {
    Column() {
      SettingsSubpageHeader({
        title: $r('app.string.about_app_title'),
        topInsetVp: this.statusBarTopInsetVp
      })

      Scroll() {
        Column() {
          Column() {
            Text($r('app.string.about_app_name_label'))
              .fontSize(14)
              .fontColor($r('app.color.ui_input_hint'))
              .width('100%')
            Text($r('app.string.EntryAbility_label'))
              .fontSize(16)
              .fontColor($r('app.color.ui_text_primary'))
              .width('100%')
              .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          this.FieldBlock($r('app.string.about_app_developer_label'), this.developerName)
          this.FieldBlock($r('app.string.about_app_website_label'), this.websiteUrl, () => {
            this.openWebsite();
          })
          this.FieldBlock($r('app.string.about_app_feedback_email_label'), this.feedbackEmail, () => {
            this.openEmail();
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 16 })
        .backgroundColor($r('app.color.ui_ime_lang_pill'))
        .border({
          width: 1,
          color: $r('app.color.ui_ime_lang_pill_stroke')
        })
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .padding({
        left: PAGE_H_MARGIN,
        right: PAGE_H_MARGIN,
        top: 4,
        bottom: 24
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_camera_page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
