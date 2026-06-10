import { common } from '@kit.AbilityKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { SymbolHeaderButton } from '../components/SymbolHeaderButton';
import { SileroModelPaths } from '../tts/SileroModelPaths';
import { TtsVoiceCatalog } from '../tts/TtsVoiceCatalog';
import { SileroInstallFailure } from '../tts/SileroModelInstaller';
import { SileroTtsNative } from '../tts/SileroTtsNative';
import { TtsVoiceManager, TtsVoiceRowState, TtsVoiceRowStatus } from '../tts/TtsVoiceManager';

const ROW_H_MARGIN: number = 12;

interface TtsVoiceRowUi {
  iso: string;
  label: string;
  state: TtsVoiceRowState;
  progress: number;
}

@Entry
@Component
struct TtsVoicePack {
  @State statusBarTopInsetVp: number = 0;
  @State rows: TtsVoiceRowUi[] = [];
  @State listLoaded: boolean = false;
  @State refreshing: boolean = false;
  private pollTimer: number = -1;

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TtsVoiceManager.init(hostCtx);
    SileroTtsNative.refreshLinkState();
    this.refreshSystemBarInsets(hostCtx);
    void this.refreshAllRows();
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    }).catch(() => {
    });
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      if (TtsVoiceManager.isDownloading()) {
        void this.refreshAllRows();
      }
    }, 300);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  onPageShow(): void {
    SileroTtsNative.refreshLinkState();
    void this.refreshAllRows();
  }

  private async refreshAllRows(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    SileroTtsNative.refreshLinkState();
    const next: TtsVoiceRowUi[] = [];
    const catalog = TtsVoiceCatalog.allEntries();
    for (let i = 0; i < catalog.length; i++) {
      const iso = catalog[i].iso;
      const status = await TtsVoiceManager.queryRowStatus(iso);
      if (!TtsVoiceManager.isOfferedState(status.state)) {
        continue;
      }
      next.push({
        iso: iso,
        label: catalog[i].label,
        state: status.state,
        progress: status.progress,
      });
    }
    this.rows = next;
    this.listLoaded = true;
    this.refreshing = false;
  }

  private confirmInstall(iso: string, label: string): void {
    if (TtsVoiceManager.isDownloading()) {
      promptAction.showToast({ message: $r('app.string.tts_voice_install_busy'), duration: 2000 });
      return;
    }
    const msg = `将安装「${label}」离线语音包到本机。`;
    promptAction.showDialog({
      title: $r('app.string.tts_voice_install_confirm_title'),
      message: msg,
      buttons: [
        { text: $r('app.string.lang_picker_cancel'), color: '#999999' },
        { text: $r('app.string.confirm_translate'), color: $r('app.color.ui_link_blue') },
      ],
    }).then((result) => {
      if (result.index === 1) {
        void this.runInstall(iso);
      }
    }).catch(() => {
    });
  }

  private toastForPostInstall(iso: string, row: TtsVoiceRowStatus): void {
    if (row.state === TtsVoiceRowState.READY) {
      promptAction.showToast({ message: $r('app.string.tts_voice_install_success'), duration: 2000 });
      return;
    }
    if (row.state === TtsVoiceRowState.NEED_REAL_DEVICE) {
      promptAction.showToast({ message: $r('app.string.tts_voice_need_real_device_hint'), duration: 5000 });
      return;
    }
    if (row.state === TtsVoiceRowState.NEED_ENGINE) {
      const hint = SileroModelPaths.langNeedsPytorchMobile(iso)
        ? $r('app.string.tts_voice_need_pytorch_hint')
        : $r('app.string.tts_voice_need_engine_hint');
      promptAction.showToast({ message: hint, duration: 5000 });
      return;
    }
    if (row.state === TtsVoiceRowState.NEED_DOWNLOAD) {
      promptAction.showToast({ message: $r('app.string.tts_voice_install_partial_missing_infer'), duration: 4000 });
      return;
    }
    promptAction.showToast({ message: $r('app.string.tts_voice_install_partial'), duration: 3500 });
  }

  private async runInstall(iso: string): Promise<void> {
    const ok = await TtsVoiceManager.downloadVoiceForIso(iso);
    await this.refreshAllRows();
    if (ok) {
      const row = await TtsVoiceManager.queryRowStatus(iso);
      this.toastForPostInstall(iso, row);
      return;
    }
    const reason = TtsVoiceManager.getLastInstallFailure();
    const code = iso.trim().toLowerCase();
    if (reason === SileroInstallFailure.NETWORK_FAILED) {
      promptAction.showToast({ message: $r('app.string.tts_voice_network_failed'), duration: 3500 });
    } else if (reason === SileroInstallFailure.MOBILE_MISSING) {
      promptAction.showToast({ message: $r('app.string.tts_voice_mobile_missing'), duration: 3500 });
    } else if (reason === SileroInstallFailure.BUSY) {
      promptAction.showToast({ message: $r('app.string.tts_voice_install_busy'), duration: 2000 });
    } else if (reason === SileroInstallFailure.NOT_BUNDLED) {
      if (code === 'ja') {
        promptAction.showToast({ message: $r('app.string.tts_voice_pack_not_bundled_ja'), duration: 4500 });
      } else if (code === 'ar') {
        promptAction.showToast({
          message: 'HAP 未含阿拉伯语 Piper 数据，请运行 setup_piper_voices.ps1 -Iso ar、pack_piper_voices.ps1 -Iso ar、pack_espeak_data.ps1 后重编',
          duration: 5500,
        });
      } else if (code === 'ca') {
        promptAction.showToast({
          message: 'HAP 未含加泰罗尼亚语 Piper 数据，请运行 setup_piper_voices.ps1 -Iso ca、pack_piper_voices.ps1 -Iso ca、pack_espeak_data.ps1 后重编',
          duration: 5500,
        });
      } else if (code === 'cs') {
        promptAction.showToast({
          message: 'HAP 未含捷克语 Piper 数据，请运行 setup_piper_voices.ps1 -Iso cs、pack_piper_voices.ps1 -Iso cs、pack_espeak_data.ps1 后重编',
          duration: 5500,
        });
      } else if (code === 'cy') {
        promptAction.showToast({
          message: 'HAP 未含威尔士语 Piper 数据，请运行 setup_piper_voices.ps1 -Iso cy、pack_piper_voices.ps1 -Iso cy、pack_espeak_data.ps1 后重编',
          duration: 5500,
        });
      } else if (code === 'da') {
        promptAction.showToast({
          message: 'HAP 未含丹麦语 Piper 数据，请运行 setup_piper_voices.ps1 -Iso da、pack_piper_voices.ps1 -Iso da、pack_espeak_data.ps1 后重编',
          duration: 5500,
        });
      } else if (TtsVoiceCatalog.findByIso(code)?.engine === 'piper') {
        const hit = TtsVoiceCatalog.findByIso(code);
        promptAction.showToast({
          message: `HAP 未含 ${hit?.label ?? code} Piper 数据，请运行 setup_piper_voices.ps1 -Iso ${code}、pack_piper_voices.ps1 与 pack_espeak_data.ps1 后重编`,
          duration: 5500,
        });
      } else {
        promptAction.showToast({ message: $r('app.string.tts_voice_pack_not_bundled'), duration: 4500 });
      }
    } else if (reason === SileroInstallFailure.COPY_FAILED && code === 'ja') {
      const detail = TtsVoiceManager.getLastInstallFailureDetail();
      const hint = detail.length > 0 ? detail : '解压或校验失败';
      promptAction.showToast({
        message: `日语语音包安装失败：${hint}`,
        duration: 5000,
      });
    } else {
      const detail = TtsVoiceManager.getLastInstallFailureDetail();
      const extra = detail.length > 0 ? ` (${detail})` : '';
      promptAction.showToast({
        message: `语音包安装失败${extra}`,
        duration: 4000,
      });
    }
  }

  @Builder
  RowStatusAction(row: TtsVoiceRowUi) {
    if (row.state === TtsVoiceRowState.DOWNLOADING) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color($r('app.color.ui_text_primary'))
    } else if (row.state === TtsVoiceRowState.READY) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(24)
        .fontColor([$r('app.color.ui_text_primary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    } else if (row.state === TtsVoiceRowState.NEED_REAL_DEVICE) {
      Text($r('app.string.tts_voice_need_real_device_short'))
        .fontSize(12)
        .fontColor($r('app.color.ui_input_hint'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else if (row.state === TtsVoiceRowState.NEED_ENGINE) {
      Text($r('app.string.tts_voice_need_engine_short'))
        .fontSize(12)
        .fontColor($r('app.color.ui_input_hint'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else if (row.state === TtsVoiceRowState.NEED_DOWNLOAD) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(26)
          .fontColor([$r('app.color.ui_text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.confirmInstall(row.iso, row.label);
      })
    }
  }

  @Builder
  VoiceRow(row: TtsVoiceRowUi) {
    Row() {
      Text(row.label)
        .fontSize(16)
        .fontColor($r('app.color.ui_text_primary'))
        .layoutWeight(1)
      Row() {
        this.RowStatusAction(row)
      }
      .width(88)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.ui_paste_chip_bg'))
    .borderRadius(14)
  }

  @Builder
  ListBody() {
    if (!this.listLoaded) {
      Row() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.ui_text_primary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 24, bottom: 24 })
    } else if (this.rows.length === 0) {
      Text($r('app.string.tts_voice_pack_empty'))
        .fontSize(14)
        .fontColor($r('app.color.ui_input_hint'))
        .width('100%')
        .padding({ top: 8, bottom: 8 })
    } else {
      ForEach(this.rows, (row: TtsVoiceRowUi) => {
        this.VoiceRow(row)
      }, (row: TtsVoiceRowUi) => `${row.iso}_${row.state}_${row.progress}`)
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
      .padding({ left: 4, right: 8, top: this.statusBarTopInsetVp + 4 })

      Text($r('app.string.tts_voice_pack_title'))
        .fontSize(18)
        .fontColor($r('app.color.ui_text_primary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: -40, bottom: 20 })

      Scroll() {
        Column({ space: 8 }) {
          this.ListBody()
        }
        .width('100%')
        .padding({ left: ROW_H_MARGIN, right: ROW_H_MARGIN, top: 4, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_pure_black'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
