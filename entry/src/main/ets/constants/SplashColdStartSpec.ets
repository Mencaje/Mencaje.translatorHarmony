/**
 * 冷启动正中 Logo（第一层 startWindowIcon 与第二层 Splash 共用 splash_logo.png）。
 * 系统层按 PNG 原始像素居中、不拉伸；第二层须用 ImageFit.None 保持一致。
 */
export class SplashColdStartSpec {
  /** 资源图 splash_logo.png 画布边长（px） */
  static readonly LOGO_CANVAS_PX: number = 600;
}
