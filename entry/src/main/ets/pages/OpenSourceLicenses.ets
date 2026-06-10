import { common } from '@kit.AbilityKit';
import { router, window } from '@kit.ArkUI';
import { OssLicenseCard } from '../components/OssLicenseCard';
import { SettingsSubpageHeader } from '../components/SettingsSubpageHeader';
import { OpenSourceLicenseData, OpenSourceLicenseEntry } from '../data/OpenSourceLicenseData';

const PAGE_H_MARGIN: number = 16;

@Entry
@Component
struct OpenSourceLicenses {
  @State statusBarTopInsetVp: number = 0;

  private readonly entries: OpenSourceLicenseEntry[] = OpenSourceLicenseData.getEntries();

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
      // ignore
    });
  }

  build() {
    Column() {
      SettingsSubpageHeader({
        title: $r('app.string.oss_screen_title'),
        topInsetVp: this.statusBarTopInsetVp
      })

      Scroll() {
        Column({ space: 14 }) {
          ForEach(this.entries, (item: OpenSourceLicenseEntry, index: number) => {
            OssLicenseCard({ entry: item })
          }, (item: OpenSourceLicenseEntry, index: number) => `${item.name}_${index}`)
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
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_camera_page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
