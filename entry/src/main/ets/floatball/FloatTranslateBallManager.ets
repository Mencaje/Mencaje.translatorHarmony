import { common, Want } from '@kit.AbilityKit';
import { floatingBall } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x4D4642;
const TAG: string = 'FloatBall';

/**
 * 翻译闪控球：HarmonyOS 6 手机官方「显示在其他应用上层」能力（API 20+）。
 * 申请：ohos.permission.USE_FLOAT_BALL + requestPermissionsFromUser
 * 展示：floatingBall.startFloatingBall（非 window.TYPE_FLOAT）
 */
export class FloatTranslateBallManager {
  private static controller: floatingBall.FloatingBallController | undefined = undefined;
  private static active: boolean = false;
  private static clickHandler: (() => void) | undefined = undefined;

  static isSupported(): boolean {
    try {
      return floatingBall.isFloatingBallEnabled();
    } catch (_e) {
      return false;
    }
  }

  static isShowing(): boolean {
    return FloatTranslateBallManager.active;
  }

  static async show(context: common.UIAbilityContext): Promise<boolean> {
    if (!FloatTranslateBallManager.isSupported()) {
      hilog.warn(DOMAIN, TAG, 'device does not support floating ball');
      return false;
    }
    try {
      if (FloatTranslateBallManager.controller === undefined) {
        const config: floatingBall.FloatingBallConfiguration = { context: context };
        FloatTranslateBallManager.controller = await floatingBall.create(config);
        FloatTranslateBallManager.registerClick(context);
      }
      const icon = await FloatTranslateBallManager.loadAppIcon(context);
      let params: floatingBall.FloatingBallParams;
      if (icon !== undefined) {
        params = {
          template: floatingBall.FloatingBallTemplate.STATIC,
          title: '译',
          icon: icon
        };
      } else {
        params = {
          template: floatingBall.FloatingBallTemplate.SIMPLE,
          title: '译'
        };
      }
      const ctrl = FloatTranslateBallManager.controller;
      if (ctrl === undefined) {
        return false;
      }
      await ctrl.startFloatingBall(params);
      FloatTranslateBallManager.active = true;
      hilog.info(DOMAIN, TAG, 'floating ball started');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'show failed: %{public}s', JSON.stringify(e));
      FloatTranslateBallManager.active = false;
      return false;
    }
  }

  static async hide(): Promise<void> {
    FloatTranslateBallManager.active = false;
    const ctrl = FloatTranslateBallManager.controller;
    if (ctrl === undefined) {
      return;
    }
    try {
      await ctrl.stopFloatingBall();
      hilog.info(DOMAIN, TAG, 'floating ball stopped');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop failed: %{public}s', JSON.stringify(e));
    }
  }

  private static registerClick(context: common.UIAbilityContext): void {
    const ctrl = FloatTranslateBallManager.controller;
    if (ctrl === undefined) {
      return;
    }
    if (FloatTranslateBallManager.clickHandler !== undefined) {
      try {
        ctrl.off('click', FloatTranslateBallManager.clickHandler);
      } catch (_e) {
      }
    }
    FloatTranslateBallManager.clickHandler = (): void => {
      const want: Want = {
        bundleName: context.applicationInfo.name,
        abilityName: 'EntryAbility'
      };
      void ctrl.restoreMainWindow(want).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'restoreMainWindow failed: %{public}s', JSON.stringify(err));
      });
    };
    ctrl.on('click', FloatTranslateBallManager.clickHandler);
  }

  private static async loadAppIcon(context: common.UIAbilityContext): Promise<image.PixelMap | undefined> {
    try {
      const buf = await context.resourceManager.getMediaContent($r('app.media.foreground').id);
      const source = image.createImageSource(buf);
      const pm = await source.createPixelMap();
      await source.release();
      return pm;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load icon failed: %{public}s', JSON.stringify(e));
      return undefined;
    }
  }
}
