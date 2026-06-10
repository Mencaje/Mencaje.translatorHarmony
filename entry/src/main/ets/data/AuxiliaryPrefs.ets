import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'mencaje_auxiliary';
const KEY_FLOAT_TRANSLATE: string = 'float_translate_enabled';

/** 辅助功能偏好（与 Android AuxiliaryPrefs 对齐的悬浮球开关） */
export class AuxiliaryPrefs {
  private static async getStore(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, STORE_NAME);
  }

  static async isFloatTranslateEnabled(context: common.Context): Promise<boolean> {
    const store = await AuxiliaryPrefs.getStore(context);
    return await store.get(KEY_FLOAT_TRANSLATE, false) as boolean;
  }

  static async setFloatTranslateEnabled(context: common.Context, enabled: boolean): Promise<void> {
    const store = await AuxiliaryPrefs.getStore(context);
    await store.put(KEY_FLOAT_TRANSLATE, enabled);
    await store.flush();
  }
}
