import { common } from '@kit.AbilityKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { AuxiliaryPrefs } from '../data/AuxiliaryPrefs';
import { FloatTranslateBallManager } from '../floatball/FloatTranslateBallManager';
import { SettingsSubpageHeader } from '../components/SettingsSubpageHeader';
import { FloatWindowPermission } from '../util/FloatWindowPermission';

const PAGE_H_MARGIN: number = 16;

@Entry
@Component
struct Accessibility {
  @State statusBarTopInsetVp: number = 0;
  @State floatTranslateOn: boolean = false;
  private updatingSwitch: boolean = false;

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.refreshSystemBarInsets(hostCtx);
    void this.syncFloatSwitch(hostCtx);
  }

  onPageShow(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void this.syncFloatSwitch(hostCtx);
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    }).catch(() => {
    });
  }

  private async syncFloatSwitch(context: common.UIAbilityContext): Promise<void> {
    const granted = await FloatWindowPermission.isGranted(context);
    const prefOn = await AuxiliaryPrefs.isFloatTranslateEnabled(context);
    if (prefOn && granted) {
      if (!FloatTranslateBallManager.isShowing()) {
        await FloatTranslateBallManager.show(context);
      }
    } else {
      await FloatTranslateBallManager.hide();
      if (!granted && prefOn) {
        await AuxiliaryPrefs.setFloatTranslateEnabled(context, false);
      }
    }
    this.updatingSwitch = true;
    this.floatTranslateOn = granted && prefOn && FloatTranslateBallManager.isShowing();
    this.updatingSwitch = false;
  }

  private showAclRequiredDialog(): void {
    promptAction.showDialog({
      title: $r('app.string.float_ball_acl_title'),
      message: $r('app.string.float_ball_acl_message'),
      buttons: [
        { text: $r('app.string.lang_picker_cancel'), color: '#999999' },
        { text: $r('app.string.float_ball_acl_ok'), color: $r('app.color.ui_link_blue') },
      ],
    }).catch(() => {
    });
  }

  private showOverlayPermissionDialog(context: common.UIAbilityContext): void {
    promptAction.showDialog({
      title: $r('app.string.float_window_permission_title'),
      message: $r('app.string.float_window_permission_message'),
      buttons: [
        { text: $r('app.string.lang_picker_cancel'), color: '#999999' },
        { text: $r('app.string.float_window_go_settings'), color: $r('app.color.ui_link_blue') },
      ],
    }).then((result) => {
      if (result.index === 1) {
        FloatWindowPermission.openAppPermissionSettings(context);
      }
    }).catch(() => {
    });
  }

  private async onFloatToggle(wantOn: boolean): Promise<void> {
    if (this.updatingSwitch) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!wantOn) {
      await AuxiliaryPrefs.setFloatTranslateEnabled(context, false);
      await FloatTranslateBallManager.hide();
      this.floatTranslateOn = false;
      return;
    }
    if (!FloatTranslateBallManager.isSupported()) {
      this.updatingSwitch = true;
      this.floatTranslateOn = false;
      this.updatingSwitch = false;
      promptAction.showToast({ message: $r('app.string.float_ball_unsupported'), duration: 3000 });
      return;
    }
    const declared = await FloatWindowPermission.isDeclaredInBundle();
    if (!declared) {
      this.updatingSwitch = true;
      this.floatTranslateOn = false;
      this.updatingSwitch = false;
      this.showAclRequiredDialog();
      return;
    }
    let granted = await FloatWindowPermission.isGranted(context);
    if (!granted) {
      granted = await FloatWindowPermission.request(context);
    }
    if (!granted) {
      this.updatingSwitch = true;
      this.floatTranslateOn = false;
      this.updatingSwitch = false;
      this.showOverlayPermissionDialog(context);
      return;
    }
    const shown = await FloatTranslateBallManager.show(context);
    if (!shown) {
      this.updatingSwitch = true;
      this.floatTranslateOn = false;
      this.updatingSwitch = false;
      promptAction.showToast({ message: $r('app.string.float_ball_show_failed'), duration: 2500 });
      return;
    }
    await AuxiliaryPrefs.setFloatTranslateEnabled(context, true);
    this.floatTranslateOn = true;
  }

  @Builder
  ToggleRow(label: ResourceStr, isOn: boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.ui_text_primary'))
        .layoutWeight(1)
        .margin({ right: 12 })
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.ui_link_blue'))
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 18, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.ui_settings_row_bg'))
    .borderRadius(14)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SettingsSubpageHeader({
        title: $r('app.string.settings_accessibility'),
        topInsetVp: this.statusBarTopInsetVp
      })

      Scroll() {
        Column() {
          this.ToggleRow($r('app.string.accessibility_float_translate'), this.floatTranslateOn, (on: boolean) => {
            void this.onFloatToggle(on);
          })
        }
        .width('100%')
        .padding({
          left: PAGE_H_MARGIN,
          right: PAGE_H_MARGIN,
          top: 4,
          bottom: 24
        })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_camera_page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
