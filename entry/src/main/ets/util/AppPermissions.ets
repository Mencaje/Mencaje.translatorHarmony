import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

/**
 * 运行时申请权限（须在 module.json5 声明 + usedScene reason）。
 * 参考：HarmonyOS 程序访问控制 / requestPermissionsFromUser。
 */
export class AppPermissions {
  static readonly CAMERA: Permissions = 'ohos.permission.CAMERA';

  static async isGranted(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const status = await atManager.checkAccessToken(context.applicationInfo.accessTokenId, permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  /** 未授权时弹出系统权限框；用户拒绝返回 false */
  static async ensure(context: common.UIAbilityContext, permission: Permissions): Promise<boolean> {
    if (await AppPermissions.isGranted(context, permission)) {
      return true;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, [permission]);
    if (result.authResults.length === 0) {
      return false;
    }
    return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  static async ensureCamera(context: common.UIAbilityContext): Promise<boolean> {
    return AppPermissions.ensure(context, AppPermissions.CAMERA);
  }
}
