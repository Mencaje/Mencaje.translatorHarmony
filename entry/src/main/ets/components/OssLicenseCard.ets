import { common } from '@kit.AbilityKit';
import { OpenSourceLicenseEntry } from '../data/OpenSourceLicenseData';
import { BrowserOpener } from '../util/BrowserOpener';

@Component
export struct OssLicenseCard {
  @Prop entry: OpenSourceLicenseEntry;

  private openUrl(url: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    BrowserOpener.openHttpUrl(ctx, url);
  }

  @Builder
  LabelText(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.ui_input_hint'))
      .width('100%')
      .margin({ top: 10 })
  }

  @Builder
  ValueText(value: string) {
    Text(value)
      .fontSize(15)
      .fontColor($r('app.color.ui_text_primary'))
      .lineHeight(22)
      .width('100%')
      .margin({ top: 2 })
  }

  @Builder
  LinkText(url: string) {
    Text(url)
      .fontSize(15)
      .fontColor($r('app.color.ui_link_blue'))
      .lineHeight(22)
      .width('100%')
      .margin({ top: 2 })
      .onClick(() => {
        this.openUrl(url);
      })
  }

  build() {
    Column() {
      Text($r('app.string.oss_field_name'))
        .fontSize(12)
        .fontColor($r('app.color.ui_input_hint'))
        .width('100%')
        .margin({ top: 0 })
      this.ValueText(this.entry.name)

      this.LabelText($r('app.string.oss_field_license'))
      this.ValueText(this.entry.license)

      this.LabelText($r('app.string.oss_field_role'))
      this.ValueText(this.entry.role)

      this.LabelText($r('app.string.oss_field_license_url'))
      this.LinkText(this.entry.licenseUrl)

      this.LabelText($r('app.string.oss_field_repo_url'))
      this.LinkText(this.entry.repoUrl)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.ui_ime_lang_pill'))
    .border({
      width: 1,
      color: $r('app.color.ui_ime_lang_pill_stroke')
    })
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }
}
