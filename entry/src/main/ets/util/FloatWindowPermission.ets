import { abilityAccessCtrl, bundleManager, common, Permissions, Want } from '@kit.AbilityKit';

/**
 * 闪控球权限 ohos.permission.USE_FLOAT_BALL（system_basic + system_grant）。
 * 须在 module.json5 声明，且调试/发布 Profile 的 allowed-acls 含同名项，否则安装报 9568289。
 * ACL 未就绪时可先从 module.json5 移除该权限以便其它功能继续调试。
 */
export class FloatWindowPermission {
  static readonly PERMISSION: Permissions = 'ohos.permission.USE_FLOAT_BALL';

  /** 当前 HAP 是否在 manifest 中声明了闪控球权限 */
  static async isDeclaredInBundle(): Promise<boolean> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
      const details = info.reqPermissionDetails;
      if (details === undefined || details.length === 0) {
        return false;
      }
      for (let i = 0; i < details.length; i++) {
        if (details[i].name === FloatWindowPermission.PERMISSION) {
          return true;
        }
      }
      return false;
    } catch (_e) {
      return false;
    }
  }

  static async isGranted(context: common.UIAbilityContext): Promise<boolean> {
    if (!(await FloatWindowPermission.isDeclaredInBundle())) {
      return false;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const status = await atManager.checkAccessToken(context.applicationInfo.accessTokenId,
      FloatWindowPermission.PERMISSION);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  /** system_grant：主要靠 Profile ACL 在安装时授予；保留 request 作兼容兜底。 */
  static async request(context: common.UIAbilityContext): Promise<boolean> {
    if (!(await FloatWindowPermission.isDeclaredInBundle())) {
      return false;
    }
    if (await FloatWindowPermission.isGranted(context)) {
      return true;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const result = await atManager.requestPermissionsFromUser(context, [FloatWindowPermission.PERMISSION]);
      if (result.authResults.length === 0) {
        return false;
      }
      return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_e) {
      return false;
    }
  }

  static openAppPermissionSettings(context: common.UIAbilityContext): void {
    const bundleName = context.applicationInfo.name;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: bundleName
      }
    };
    context.startAbility(want).catch(() => {
      const fallback: Want = {
        action: 'action.settings.app.info',
        parameters: {
          settingsParamBundleName: bundleName
        }
      };
      context.startAbility(fallback).catch(() => {
      });
    });
  }
}
