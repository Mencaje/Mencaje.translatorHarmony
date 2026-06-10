import { common } from '@kit.AbilityKit';
import { router, window } from '@kit.ArkUI';
import { SettingsSubpageHeader } from '../components/SettingsSubpageHeader';

@Entry
@Component
struct Settings {
  @State statusBarTopInsetVp: number = 0;

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.refreshSystemBarInsets(hostCtx);
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    }).catch(() => {
    });
  }

  @Builder
  SettingsRow(label: ResourceStr, onTap: () => void) {
    Text(label)
      .fontSize(16)
      .fontColor($r('app.color.ui_text_primary'))
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 18 })
      .backgroundColor($r('app.color.ui_settings_row_bg'))
      .borderRadius(14)
      .onClick(onTap)
  }

  build() {
    Column() {
      SettingsSubpageHeader({
        title: $r('app.string.settings_title'),
        topInsetVp: this.statusBarTopInsetVp
      })

      Column({ space: 12 }) {
        this.SettingsRow($r('app.string.settings_open_source'), () => {
          router.pushUrl({ url: 'pages/OpenSourceLicenses' });
        })
        this.SettingsRow($r('app.string.settings_tts_languages'), () => {
          router.pushUrl({ url: 'pages/TtsVoicePack' });
        })
        this.SettingsRow($r('app.string.settings_nllb_model'), () => {
          router.pushUrl({ url: 'pages/NllbModelPack' });
        })
        this.SettingsRow($r('app.string.settings_accessibility'), () => {
          router.pushUrl({ url: 'pages/Accessibility' });
        })
        this.SettingsRow($r('app.string.settings_about'), () => {
          router.pushUrl({ url: 'pages/AboutApp' });
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Text($r('app.string.settings_footer_hint'))
        .fontSize(13)
        .fontColor($r('app.color.ui_input_hint'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_pure_black'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
