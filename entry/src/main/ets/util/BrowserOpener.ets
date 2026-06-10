import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x4D424F; // MBO

/** 使用系统默认浏览器 / 邮件客户端打开链接 */
export class BrowserOpener {
  static openHttpUrl(context: common.UIAbilityContext, url: string): void {
    if (url.length === 0) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
    };
    context.startAbility(want).catch((err: Error) => {
      hilog.error(DOMAIN, 'BrowserOpener', 'openHttpUrl failed: %{public}s', JSON.stringify(err));
    });
  }

  static openEmail(context: common.UIAbilityContext, email: string): void {
    if (email.length === 0) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.sendToData',
      uri: `mailto:${email}`,
    };
    context.startAbility(want).catch((err: Error) => {
      hilog.error(DOMAIN, 'BrowserOpener', 'openEmail failed: %{public}s', JSON.stringify(err));
    });
  }
}
