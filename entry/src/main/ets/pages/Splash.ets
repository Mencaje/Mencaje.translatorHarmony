import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { CTranslate2Engine } from '../translation/CTranslate2Engine';
import { NllbModelInstaller } from '../translation/NllbModelInstaller';
import { TranslateLanguages } from '../translation/TranslateLanguages';

/**
 * 第二层冷启动：仅正中 Logo，与系统 startWindowIcon（splash_logo）同图、同尺寸、同居中规则。
 */
const SPLASH_MIN_MS: number = 380;

@Entry
@Component
struct Splash {
  aboutToAppear(): void {
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const minDelay = new Promise<void>((resolve) => {
      setTimeout(() => resolve(), SPLASH_MIN_MS);
    });
    const langReady = TranslateLanguages.loadFromRawfile(hostCtx).catch(() => {
      // 已在 EntryAbility 预加载，失败不阻塞
    });
    const nllbReady = NllbModelInstaller.whenInstallDone();
    Promise.all([minDelay, langReady, nllbReady]).then(() => {
      CTranslate2Engine.init(hostCtx);
      router.replaceUrl({ url: 'pages/Index' });
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.splash_logo'))
        .objectFit(ImageFit.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_pure_black'))
  }
}
