import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { CTranslate2Engine } from '../translation/CTranslate2Engine';
import { NllbModelInstaller } from '../translation/NllbModelInstaller';
import { TranslateLanguages } from '../translation/TranslateLanguages';
import { SileroTtsEngine } from '../tts/SileroTtsEngine';
import { SileroTtsNative } from '../tts/SileroTtsNative';
import { FloatTranslateBallManager } from '../floatball/FloatTranslateBallManager';
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    SileroTtsEngine.init(this.context);
    const linked = SileroTtsEngine.isLibraryLinked();
    const buildInfo = SileroTtsNative.getBuildInfo();
    hilog.info(DOMAIN, 'testTag', 'Silero TTS linked=%{public}s build=%{public}s',
      String(linked), buildInfo);
    if (!linked) {
      if (buildInfo.indexOf('[stub-x86_64]') >= 0) {
        hilog.error(DOMAIN, 'testTag',
          'TTS on x86_64 emulator (no Sherpa). Use USB arm64 phone: Run target = your device, not Emulator. build=%{public}s',
          buildInfo);
      } else if (buildInfo.indexOf('NO inference') >= 0) {
        hilog.error(DOMAIN, 'testTag',
          'TTS stub on device — run scripts/prepare_native_tts.ps1, DevEco Clean+Rebuild, reinstall on phone. build=%{public}s',
          buildInfo);
      } else {
        hilog.error(DOMAIN, 'testTag', 'TTS inference NOT linked. build=%{public}s', buildInfo);
      }
    } else if (buildInfo.indexOf('[summertts]') >= 0 || buildInfo.indexOf('[piperplus]') >= 0) {
      hilog.info(DOMAIN, 'testTag', 'TTS engine OK. build=%{public}s', buildInfo);
      if (buildInfo.indexOf('abi=x86_64') >= 0 && buildInfo.indexOf('piperplus') < 0) {
        hilog.warn(DOMAIN, 'testTag',
          'TTS x86_64 slice: missing piper-plus — run scripts\\prepare_native_tts.ps1 then Clean+Rebuild');
      }
    }
    void SileroTtsEngine.warmUp();
    CTranslate2Engine.init(this.context);
    const ct2Linked = CTranslate2Engine.isCt2LibraryLinked();
    const ct2Build = CTranslate2Engine.getBuildInfo();
    hilog.info(DOMAIN, 'testTag', 'CT2 linked=%{public}s build=%{public}s',
      String(ct2Linked), ct2Build);
    if (!ct2Linked) {
      hilog.error(DOMAIN, 'testTag',
        'CT2 NOT linked — offline NLLB disabled. %{public}s. Run scripts\\build_ctranslate2_ohos.ps1 -Abi arm64-v8a, DevEco Clean Project → Rebuild, uninstall app → reinstall on phone.',
        ct2Build);
    }
    NllbModelInstaller.beginInstallOnStartup(this.context);
    TranslateLanguages.loadFromRawfile(this.context).then(() => {
      CTranslate2Engine.preloadInBackground();
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'TranslateLanguages load failed: %{public}s', JSON.stringify(err));
      CTranslate2Engine.preloadInBackground();
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    void FloatTranslateBallManager.hide();
    SileroTtsEngine.shutdown();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Splash', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      windowStage.getMainWindow((winErr, mainWindow) => {
        if (winErr.code || mainWindow === undefined) {
          return;
        }
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#FF000000',
          navigationBarColor: '#FF242426',
          statusBarContentColor: '#FFFFFFFF',
          navigationBarContentColor: '#FFFFFFFF'
        });
      });
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}