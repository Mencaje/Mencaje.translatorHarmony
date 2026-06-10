import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppPermissions } from '../util/AppPermissions';

const DOMAIN = 0x43414D; // CAM
const LOG_DOMAIN_UI = 0x0000;
const LOG_TAG_UI = 'testTag';

/** cameraPicker 成功时 resultCode 一般为 0 */
const PICKER_RESULT_OK: number = 0;
const CAPTURE_FILE_POLL_MS: number = 80;
const CAPTURE_FILE_POLL_MAX: number = 10;

export class CameraLaunchResult {
  uri: string | null = null;
  /** 供 UI 展示 toast 的资源名，空表示无需提示 */
  messageRes: string = '';

  constructor(uri: string | null = null, messageRes: string = '') {
    this.uri = uri;
    this.messageRes = messageRes;
  }
}

/**
 * 拍照 / 相册选图（对齐 Android：短按相机、长按相册）。
 * 须在 UIAbility 界面内调用 cameraPicker.pick（华为文档要求）。
 */
export class CameraLaunch {
  private static captureFileReady(path: string): boolean {
    try {
      fileIo.accessSync(path);
      return fileIo.statSync(path).size > 0;
    } catch (_e) {
      return false;
    }
  }

  /** 系统相机要求 saveUri 对应沙箱文件已存在且可写，否则 resultUri 为空且不会写入。 */
  private static prepareWritableCaptureFile(path: string): boolean {
    try {
      const file = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.closeSync(file);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'CameraLaunch', 'prepareWritableCaptureFile failed: %{public}s', JSON.stringify(e));
      hilog.error(LOG_DOMAIN_UI, LOG_TAG_UI, 'CameraLaunch prepare capture file failed');
      return false;
    }
  }

  private static sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => setTimeout(resolve, ms));
  }

  private static async waitCaptureFileReady(path: string): Promise<boolean> {
    for (let i = 0; i < CAPTURE_FILE_POLL_MAX; i++) {
      if (CameraLaunch.captureFileReady(path)) {
        return true;
      }
      await CameraLaunch.sleepMs(CAPTURE_FILE_POLL_MS);
    }
    return false;
  }

  private static resolveCaptureUri(resultUri: string, saveUri: string, capturePath: string): string {
    if (resultUri.length > 0) {
      return resultUri;
    }
    if (saveUri.length > 0 && CameraLaunch.captureFileReady(capturePath)) {
      return saveUri;
    }
    if (CameraLaunch.captureFileReady(capturePath)) {
      try {
        return fileUri.getUriFromPath(capturePath);
      } catch (_e) {
        return '';
      }
    }
    return '';
  }

  /**
   * 系统相机拍照。context 必须为 UIAbilityContext（getContext(this)）。
   */
  static async takePhoto(context: common.UIAbilityContext): Promise<CameraLaunchResult> {
    try {
      if (typeof canIUse === 'function' && !canIUse('SystemCapability.Multimedia.Camera.Core')) {
        hilog.warn(DOMAIN, 'CameraLaunch', 'Camera.Core not supported on device');
        return new CameraLaunchResult(null, 'camera_unavailable');
      }
    } catch (_cap) {
      // ignore
    }

    const granted = await AppPermissions.ensureCamera(context);
    if (!granted) {
      return new CameraLaunchResult(null, 'camera_permission_denied');
    }

    const capturePath = `${context.filesDir}/mencaje_capture_${Date.now()}.jpg`;
    if (!CameraLaunch.prepareWritableCaptureFile(capturePath)) {
      return new CameraLaunchResult(null, 'camera_open_failed');
    }
    let saveUri: string;
    try {
      saveUri = fileUri.getUriFromPath(capturePath);
    } catch (e) {
      hilog.error(DOMAIN, 'CameraLaunch', 'getUriFromPath failed: %{public}s', JSON.stringify(e));
      saveUri = '';
    }
    hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'CameraLaunch pick saveUri ready=%{public}s',
      saveUri.length > 0 ? '1' : '0');

    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
      };
      if (saveUri.length > 0) {
        profile.saveUri = saveUri;
      }
      const result = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        profile,
      );
      const pickUri = result?.resultUri ?? '';
      hilog.info(DOMAIN, 'CameraLaunch', 'pick resultCode=%{public}d uri=%{public}s',
        result?.resultCode ?? -1, pickUri);
      hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'CameraLaunch pick code=%{public}d uriLen=%{public}d',
        result?.resultCode ?? -1, pickUri.length);

      if (result === undefined) {
        return new CameraLaunchResult(null, 'camera_open_failed');
      }
      if (result.resultCode !== PICKER_RESULT_OK) {
        return new CameraLaunchResult(null, '');
      }
      if (pickUri.length === 0) {
        await CameraLaunch.waitCaptureFileReady(capturePath);
      }
      const resolved = CameraLaunch.resolveCaptureUri(pickUri, saveUri, capturePath);
      if (resolved.length > 0) {
        hilog.info(LOG_DOMAIN_UI, LOG_TAG_UI, 'CameraLaunch ok resolved len=%{public}d', resolved.length);
        return new CameraLaunchResult(resolved, '');
      }
      hilog.warn(LOG_DOMAIN_UI, LOG_TAG_UI,
        'CameraLaunch no photo path ready=%{public}s', CameraLaunch.captureFileReady(capturePath) ? '1' : '0');
      return new CameraLaunchResult(null, '');
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, 'CameraLaunch', 'takePhoto failed code=%{public}d %{public}s',
        err.code ?? -1, JSON.stringify(e));
      return new CameraLaunchResult(null, 'camera_open_failed');
    }
  }

  static async pickFromAlbum(_context: common.UIAbilityContext): Promise<CameraLaunchResult> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      const uris = result.photoUris;
      if (uris !== undefined && uris.length > 0 && uris[0].length > 0) {
        return new CameraLaunchResult(uris[0], '');
      }
      return new CameraLaunchResult(null, '');
    } catch (e) {
      hilog.error(DOMAIN, 'CameraLaunch', 'pickFromAlbum failed: %{public}s', JSON.stringify(e));
      return new CameraLaunchResult(null, 'album_open_failed');
    }
  }
}
