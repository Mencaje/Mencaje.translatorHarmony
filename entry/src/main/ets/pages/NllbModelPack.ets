import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { SymbolHeaderButton } from '../components/SymbolHeaderButton';
import { CTranslate2Engine } from '../translation/CTranslate2Engine';
import { NllbInstallFailure, NllbModelInstaller } from '../translation/NllbModelInstaller';
import { NllbModelPaths } from '../translation/NllbModelPaths';

@Entry
@Component
struct NllbModelPack {
  @State statusBarTopInsetVp: number = 0;
  @State installed: boolean = false;
  @State ct2Linked: boolean = false;
  @State bundledInHap: boolean = false;
  @State installing: boolean = false;
  @State progress: number = 0;
  @State modelDir: string = '';
  @State resourceDirHint: string = '';
  @State readyInPlace: boolean = false;

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    CTranslate2Engine.init(hostCtx);
    NllbModelInstaller.prepareModelDirectories(hostCtx);
    this.refreshSystemBarInsets(hostCtx);
    this.refreshStatus(hostCtx);
  }

  onPageShow(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.refreshStatus(hostCtx);
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    }).catch(() => {
    });
  }

  private refreshStatus(ctx: common.UIAbilityContext): void {
    this.installed = NllbModelInstaller.isInstalled(ctx.filesDir);
    this.ct2Linked = CTranslate2Engine.isCt2LibraryLinked();
    this.bundledInHap = NllbModelInstaller.isRawBundledInHap(ctx);
    this.modelDir = CTranslate2Engine.getModelDir().length > 0 ?
      CTranslate2Engine.getModelDir() : NllbModelPaths.modelRoot(ctx.filesDir);
    this.resourceDirHint = ctx.resourceDir ?? '';
    this.readyInPlace = CTranslate2Engine.isReadyForOffline();
    CTranslate2Engine.refreshModelPresence();
    this.readyInPlace = CTranslate2Engine.isReadyForOffline();
  }

  private finishInstall(hostCtx: common.UIAbilityContext, ok: boolean): void {
    this.installing = false;
    this.refreshStatus(hostCtx);
    if (ok) {
      promptAction.showToast({ message: $r('app.string.nllb_install_success'), duration: 2500 });
      return;
    }
    const kind = NllbModelInstaller.getLastFailure();
    if (kind === NllbInstallFailure.BUSY) {
      promptAction.showToast({ message: $r('app.string.nllb_install_busy'), duration: 2000 });
    } else if (kind === NllbInstallFailure.NOT_BUNDLED) {
      promptAction.showToast({ message: $r('app.string.nllb_import_need_files'), duration: 5000 });
    } else {
      promptAction.showToast({ message: $r('app.string.nllb_install_failed'), duration: 4000 });
    }
  }

  private startInstall(): void {
    if (this.installing) {
      return;
    }
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (NllbModelInstaller.isInstalled(hostCtx.filesDir)) {
      promptAction.showToast({ message: $r('app.string.nllb_model_ready'), duration: 2500 });
      return;
    }
    if (!NllbModelInstaller.isRawBundledInHap(hostCtx)) {
      promptAction.showToast({ message: $r('app.string.nllb_install_not_bundled'), duration: 5000 });
      return;
    }
    this.installing = true;
    this.progress = 0;
    NllbModelInstaller.installIfNeeded(hostCtx, (p: number) => {
      this.progress = p;
    }, (ok: boolean) => {
      this.finishInstall(hostCtx, ok);
    });
  }

  private async startImportFromPicker(): Promise<void> {
    if (this.installing) {
      return;
    }
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(hostCtx);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 4;
    try {
      const uris = await documentPicker.select(options);
      if (uris === undefined || uris.length === 0) {
        return;
      }
      this.installing = true;
      this.progress = 0;
      const ok = await NllbModelInstaller.installFromPickerUris(hostCtx, uris, (p: number) => {
        this.progress = p;
      });
      this.finishInstall(hostCtx, ok);
    } catch (_e) {
      promptAction.showToast({ message: $r('app.string.nllb_import_cancelled'), duration: 2000 });
    }
  }

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
      .padding({ left: 4, right: 8, top: 4 })

      Text($r('app.string.settings_nllb_model'))
        .fontSize(18)
        .fontColor($r('app.color.ui_text_primary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: -40, bottom: 20 })

      Column({ space: 14 }) {
        Text(this.installed ? $r('app.string.nllb_model_ready') : $r('app.string.nllb_model_missing'))
          .fontSize(15)
          .fontColor($r('app.color.ui_text_primary'))
          .width('100%')

        Text(this.ct2Linked ? $r('app.string.nllb_ct2_linked') : $r('app.string.nllb_ct2_not_linked'))
          .fontSize(13)
          .fontColor($r('app.color.ui_input_hint'))
          .width('100%')

        if (this.modelDir.length > 0) {
          Text(this.modelDir)
            .fontSize(12)
            .fontColor($r('app.color.ui_input_hint'))
            .width('100%')
            .maxLines(3)
        }

        if (!this.bundledInHap && !this.installed) {
          Text($r('app.string.nllb_dev_slim_hap'))
            .fontSize(14)
            .fontColor('#E6A23C')
            .width('100%')
        }

        if (this.installing) {
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color($r('app.color.ui_link_blue'))
          Text(`${this.progress}%`)
            .fontSize(13)
            .fontColor($r('app.color.ui_input_hint'))
        }

        Button(this.installed ? $r('app.string.nllb_recheck') :
          (this.bundledInHap ? $r('app.string.nllb_install_button') : $r('app.string.nllb_recheck')))
          .width('100%')
          .height(48)
          .enabled(!this.installing && (this.installed || this.bundledInHap))
          .onClick(() => {
            if (this.installed) {
              const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              this.refreshStatus(hostCtx);
              promptAction.showToast({ message: $r('app.string.nllb_model_ready'), duration: 2000 });
              return;
            }
            this.startInstall();
          })

        if (!this.installed) {
          Button($r('app.string.nllb_import_button'))
            .width('100%')
            .height(48)
            .enabled(!this.installing)
            .onClick(() => {
              void this.startImportFromPicker();
            })
        }

        Text($r('app.string.nllb_install_hint'))
          .fontSize(13)
          .fontColor($r('app.color.ui_input_hint'))
          .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarTopInsetVp })
    .backgroundColor($r('app.color.ui_pure_black'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
