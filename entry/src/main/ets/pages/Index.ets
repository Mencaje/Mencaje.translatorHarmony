import { common } from '@kit.AbilityKit';
import { ImmersiveLightIconButton } from '../components/ImmersiveLightIconButton';
import { LanguagePickerOverlay } from '../components/LanguagePickerOverlay';
import { SpeakActionButton } from '../components/SpeakActionButton';
import { SymbolHeaderButton } from '../components/SymbolHeaderButton';
import { HomeTranslatePlan, HomeTranslatePlanKind, HomeTranslatePlanner } from '../translation/HomeTranslatePlanner';
import { InputLanguageDetector } from '../translation/InputLanguageDetector';
import { CTranslate2Engine } from '../translation/CTranslate2Engine';
import { OnDeviceTranslator } from '../translation/OnDeviceTranslator';
import { CameraLaunch } from '../translation/CameraLaunch';
import { AppPermissions } from '../util/AppPermissions';
import { TranslateLanguageOption, TranslateLanguages } from '../translation/TranslateLanguages';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { KeyboardAvoidMode, promptAction, router, window } from '@kit.ArkUI';
import { SileroModelPaths } from '../tts/SileroModelPaths';
import { SileroModelInstaller } from '../tts/SileroModelInstaller';
import { SileroSpeakFailure, SileroTtsEngine } from '../tts/SileroTtsEngine';
import { SileroTtsNative } from '../tts/SileroTtsNative';
import { TtsSpeakPhase, TtsSpeakUi } from '../tts/TtsSpeakUi';
import { TtsVoiceCatalog } from '../tts/TtsVoiceCatalog';

/** 翻译结果行（对照双译时可能两行） */
class TranslationResultRow {
  targetLabel: string = '';
  targetIso: string = '';
  displayedText: string = '';
  showActions: boolean = false;
}

class TranslateOutputItem {
  targetIso: string = '';
  text: string = '';
}

/** 与 Android MainActivity 一致：展开 margin 动画 */
const EXPAND_MARGIN_ANIM_MS: number = 280;
/** 收起 margin 动画 */
const COLLAPSE_MARGIN_ANIM_MS: number = 320;
/** 收起结束后释放 margin 锁（Android postDelayed 420ms） */
const COLLAPSE_RELEASE_DELAY_MS: number = 420;
/** BottomSheet peek 下限 dp→vp */
const MIN_SHEET_HEIGHT_VP: number = 280;
const COLLAPSE_FIXED_NUDGE_VP: number = 52;
const COLLAPSE_RATIO_NUDGE: number = 0.16;
const COLLAPSE_MIN_MARGIN_VP: number = 198;
const COLLAPSE_MIN_STRIP_RATIO: number = 0.74;
/** BlackRoundedBottomPanel 底圆角 36dp */
const PANEL_BOTTOM_RADIUS_VP: number = 36;
/** 与 Android inputScroll paddingHorizontal 20dp 一致：源语标签 / 输入 / 译文左对齐 */
const INPUT_CONTENT_PAD_H: number = 20;

@Entry
@Component
struct Index {
  @State inputText: string = '';
  @State sourceNllbCode: string = 'zho_Hans';
  @State targetNllbCode: string = 'eng_Latn';
  @State langChoices: TranslateLanguageOption[] = TranslateLanguages.getLanguageChoices();
  @State pairLangChoices: TranslateLanguageOption[] =
    TranslateLanguages.getPairLanguageChoices('zho_Hans', 'eng_Latn');
  @State langPickerVisible: boolean = false;
  @State langPickerSide: string = 'from';
  @State langPickerTitle: string = '';
  @State langPickerForDetectedSource: boolean = false;
  @State displayedSourceLangLabel: string = '中文（简体）';
  /** 最近一次翻译实际使用的源语 iso（可能与底栏「原文」互换，见 Android updateSourceLangLabelForPlan） */
  @State activePlanSourceIso: string = '';
  @State sourceLangChipText: string = '';
  @State showSourceLangChip: boolean = false;
  @State showConfirmTranslate: boolean = false;
  @State translationBlockVisible: boolean = false;
  @State translationProgressVisible: boolean = false;
  @State translationRows: TranslationResultRow[] = [];
  /** 单语向结果文案（打字机直接绑 @State，避免 ForEach 不刷新只显示首字） */
  @State primaryResultText: string = '';
  @State primaryResultLabel: string = '';
  /** 单语向译文实际语种（反向翻译时与底栏「译文」可能相反，朗读须用此项） */
  @State primaryResultTargetIso: string = '';
  @State primaryResultShowActions: boolean = false;
  @State inputExpanded: boolean = false;
  @State keyboardHeightVp: number = 0;
  @State langBarOpacity: number = 0;
  @State bottomStripOpacity: number = 1;
  @State interactionLocked: boolean = false;
  /** 与 Android blackInputHost bottomMargin 同源；勿从 0 起步否则首帧盖住底栏 */
  @State blackHostBottomMarginVp: number = COLLAPSE_MIN_MARGIN_VP;
  @State stripPeekHeightVp: number = 280;
  @State homeTitleOpacity: number = 1;
  @State langBarTranslateYVp: number = 0;
  @State viewportHeightVp: number = 800;
  @State statusBarTopInsetVp: number = 0;
  @State navBarBottomInsetVp: number = 0;

  private textAreaController: TextAreaController = new TextAreaController();
  private lastKeyboardHeightVp: number = 0;
  private imePeakVp: number = 0;
  private expandedSessionActive: boolean = false;
  private collapseMarginAnimRunning: boolean = false;
  private win: window.Window | null = null;
  private keyboardAreaListener: ((data: window.AvoidAreaOptions) => void) | null = null;
  private windowSizeListener: (() => void) | null = null;
  private translateInFlight: boolean = false;
  private typewriterActive: boolean = false;
  private twFull: string = '';
  private twIndex: number = 0;
  private twTimerId: number = -1;
  private lastSuccessfulTranslationKey: string | null = null;
  private userOverrideSourceIso: string | null = null;
  private lastAutoDetectedIso: string | null = null;
  /** 上一轮翻译实际采用的源语（弹窗默认勾选、与 Android plan.source 一致） */
  private lastUsedSourceIso: string | null = null;
  private overrideBoundText: string | null = null;
  /** 底栏语言对调后强制要求重新点确定 */
  private langPairRevision: number = 0;

  aboutToAppear(): void {
    TtsSpeakUi.ensureStorage();
    // Android 用手动 bottomMargin；勿用系统默认 OFFSET/RESIZE 把整页顶出屏幕
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);

    const hostCtx = this.getUIContext().getHostContext();
    if (hostCtx) {
      TranslateLanguages.loadFromRawfile(hostCtx as common.UIAbilityContext).then(() => {
        this.langChoices = TranslateLanguages.getLanguageChoices();
      });
    this.refreshPairLangChoices();
    this.refreshDisplayedSourceLangLabel();
    }

    const ctx = hostCtx;
    window.getLastWindow(ctx).then((w: window.Window) => {
      this.win = w;
      this.keyboardAreaListener = (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          const hVp = this.getUIContext().px2vp(data.area.bottomRect.height);
          this.onKeyboardHeightVp(hVp);
          return;
        }
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
          data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.refreshSystemBarInsets();
        }
      };
      w.on('avoidAreaChange', this.keyboardAreaListener);
      const kbArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.onKeyboardHeightVp(this.getUIContext().px2vp(kbArea.bottomRect.height));
      this.refreshSystemBarInsets();
      this.windowSizeListener = () => {
        this.refreshStripPeekHeight();
      };
      w.on('windowSizeChange', this.windowSizeListener);
      this.refreshStripPeekHeight();
      this.blackHostBottomMarginVp = this.computeCollapsedBottomMarginVp(0);
    });
  }

  aboutToDisappear(): void {
    this.cancelTypewriter();
    if (this.win !== null) {
      if (this.keyboardAreaListener !== null) {
        this.win.off('avoidAreaChange', this.keyboardAreaListener);
      }
      if (this.windowSizeListener !== null) {
        this.win.off('windowSizeChange', this.windowSizeListener);
      }
    }
  }

  private refreshSystemBarInsets(): void {
    if (this.win === null) {
      return;
    }
    const sys = this.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const nav = this.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
    this.navBarBottomInsetVp = this.getUIContext().px2vp(nav.bottomRect.height);
  }

  /** Android: max(usable/3, 280dp) 且不超过 usable*0.55 */
  private refreshStripPeekHeight(): void {
    if (this.win === null) {
      return;
    }
    const rect = this.win.getWindowProperties().windowRect;
    const totalVp = this.getUIContext().px2vp(rect.height);
    const usableVp = totalVp * 0.88;
    const thirdVp = usableVp / 3;
    this.stripPeekHeightVp = Math.min(
      Math.max(thirdVp, MIN_SHEET_HEIGHT_VP),
      usableVp * 0.55
    );
    this.viewportHeightVp = totalVp;
    if (!this.inputExpanded) {
      this.blackHostBottomMarginVp = this.computeCollapsedBottomMarginVp(this.keyboardHeightVp);
    }
  }

  /** 展开输入后光标应在文末，勿落在「你好」等文字最前 */
  private moveCaretToEnd(): void {
    try {
      const len = this.inputText.length;
      this.textAreaController.caretPosition(len);
    } catch (_e) {
    }
  }

  /** 首页折叠：Scroll 内容最小高度撑满黑区，空白处点击即可展开 */
  private getInputScrollMinHeightVp(): number {
    const host = this.getBlackHostLayoutHeightVp();
    const chrome = this.inputExpanded ? 140 : 56;
    return Math.max(160, host - chrome);
  }

  /**
   * Android adjustedCollapsedBlackBottomMargin:
   * pulled = raw - 52dp - raw*0.16，且 >= max(198dp, strip*0.74)
   */
  private computeCollapsedBottomMarginVp(imeBottomVp: number): number {
    const raw = this.stripPeekHeightVp;
    if (raw <= 0) {
      return Math.max(imeBottomVp, 0);
    }
    const totalNudgeVp = COLLAPSE_FIXED_NUDGE_VP + raw * COLLAPSE_RATIO_NUDGE;
    const minMarginVp = Math.max(COLLAPSE_MIN_MARGIN_VP, raw * COLLAPSE_MIN_STRIP_RATIO);
    const pulled = Math.max(raw - totalNudgeVp, minMarginVp);
    return Math.max(imeBottomVp, pulled);
  }

  /** 展开态：先动画到 0，键盘起来后再用 IME 高度（与 Android computeHostBottomMargin 一致） */
  private computeExpandedBottomMarginVp(): number {
    if (this.keyboardHeightVp > 0.5) {
      return this.keyboardHeightVp;
    }
    return 0;
  }

  /** 黑区实际高度 = 视口 − bottomMargin（勿 height 100% + margin，会盖住底栏） */
  private getBlackHostLayoutHeightVp(): number {
    const viewport = this.viewportHeightVp;
    if (viewport <= 0) {
      return 0;
    }
    return Math.max(160, viewport - this.blackHostBottomMarginVp);
  }

  private onKeyboardHeightVp(hVp: number): void {
    const prevImeVp = this.lastKeyboardHeightVp;
    this.updateLangBarFollowKeyboard(hVp);
    this.keyboardHeightVp = hVp;
    this.lastKeyboardHeightVp = hVp;
    if (this.inputExpanded && !this.collapseMarginAnimRunning && !this.interactionLocked) {
      this.blackHostBottomMarginVp = this.computeExpandedBottomMarginVp();
    }
  }

  private updateLangBarFollowKeyboard(hVp: number): void {
    if (!this.inputExpanded) {
      if (hVp === 0) {
        this.imePeakVp = 0;
        this.langBarOpacity = 0;
      }
      return;
    }

    if (hVp > 0.5) {
      this.imePeakVp = Math.max(this.imePeakVp, hVp);
      this.langBarOpacity = 1;
      this.langBarTranslateYVp = 0;
    } else if (hVp < this.lastKeyboardHeightVp && this.imePeakVp > 0) {
      const denom = Math.max(this.imePeakVp, 1);
      this.langBarOpacity = Math.min(1, Math.max(0, hVp / denom));
      this.langBarTranslateYVp = (this.imePeakVp - hVp) * 0.38;
    }

    if (hVp === 0) {
      this.imePeakVp = 0;
      this.langBarOpacity = 0;
      this.langBarTranslateYVp = 0;
    }
  }

  /**
   * @Entry 页面返回（true=页面自己处理，false=系统默认退出）。
   * 勿用 UIAbility.onBackPressed：SDK12+ 下 true 会把应用切到后台。
   */
  onBackPress(): boolean {
    return this.handleBackPress();
  }

  /**
   * 展开会话：键盘开着只关键盘；键盘已关再按返回才升起回首页。
   */
  private handleBackPress(): boolean {
    if (this.interactionLocked || this.collapseMarginAnimRunning) {
      return true;
    }
    if (!this.expandedSessionActive) {
      return false;
    }
    if (this.keyboardHeightVp > 0.5) {
      this.dismissKeyboardOnly();
    } else {
      this.performCollapseMarginAndChrome();
    }
    return true;
  }

  /** Android expandInputArea: bottomMargin startOverlap→0，280ms Decelerate */
  private expandInputArea(): void {
    if (this.interactionLocked || this.inputExpanded) {
      return;
    }
    this.collapseMarginAnimRunning = false;
    this.interactionLocked = true;
    this.expandedSessionActive = true;
    this.inputExpanded = true;
    this.bottomStripOpacity = 0;
    const startInset = this.computeCollapsedBottomMarginVp(this.lastKeyboardHeightVp);
    this.blackHostBottomMarginVp = startInset;

    this.getUIContext().animateTo({
      duration: EXPAND_MARGIN_ANIM_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.blackHostBottomMarginVp = this.computeExpandedBottomMarginVp();
        if (this.keyboardHeightVp > 0.5) {
          this.langBarOpacity = 1;
        }
        this.interactionLocked = false;
        this.requestInputFocus(true);
      }
    }, () => {
      this.blackHostBottomMarginVp = 0;
    });
  }

  /** @param placeCaretAtEnd 仅展开/粘贴后置尾；用户点选中间编辑时不要置尾 */
  private requestInputFocus(placeCaretAtEnd: boolean = false): void {
    if (!this.inputExpanded) {
      return;
    }
    this.getUIContext().getFocusController().requestFocus('mainInputArea');
    if (placeCaretAtEnd) {
      setTimeout(() => {
        this.moveCaretToEnd();
      }, 48);
    }
  }

  /** 第一次返回（键盘开着）：只收键盘，保持展开态 */
  private dismissKeyboardOnly(): void {
    if (!this.expandedSessionActive) {
      return;
    }
    try {
      this.textAreaController.stopEditing();
    } catch (_e) {
    }
    this.getUIContext().getFocusController().clearFocus();
  }

  /**
   * Android performCollapseMarginAndChrome:
   * 立即切折叠 chrome + 露出底栏，margin 从当前→adjustedCollapsed，320ms。
   */
  private performCollapseMarginAndChrome(): void {
    if (!this.inputExpanded && !this.expandedSessionActive) {
      return;
    }
    if (this.collapseMarginAnimRunning) {
      return;
    }
    this.collapseMarginAnimRunning = true;
    this.interactionLocked = true;
    this.keyboardHeightVp = 0;
    this.langBarOpacity = 0;
    this.imePeakVp = 0;
    this.lastKeyboardHeightVp = 0;

    const endCollapsed = this.computeCollapsedBottomMarginVp(0);
    this.bottomStripOpacity = 1;
    this.homeTitleOpacity = 1;
    this.inputExpanded = false;
    try {
      this.textAreaController.stopEditing();
      this.textAreaController.caretPosition(0);
    } catch (_e) {
    }
    this.getUIContext().getFocusController().clearFocus();

    this.getUIContext().animateTo({
      duration: COLLAPSE_MARGIN_ANIM_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.blackHostBottomMarginVp = endCollapsed;
        setTimeout(() => {
          this.collapseMarginAnimRunning = false;
          this.expandedSessionActive = false;
          this.interactionLocked = false;
        }, COLLAPSE_RELEASE_DELAY_MS);
      }
    }, () => {
      this.blackHostBottomMarginVp = endCollapsed;
    });
  }

  private onInputAreaTapped(): void {
    if (this.interactionLocked) {
      return;
    }
    if (!this.inputExpanded) {
      this.expandInputArea();
    }
  }

  private applyPastedText(text: string): void {
    if (text.length > 0) {
      this.clearTranslationUi();
      this.onInputTextChanged(text);
      if (!this.inputExpanded) {
        this.expandInputArea();
      } else {
        this.requestInputFocus(true);
      }
      this.confirmTranslateFromInput();
    } else {
      promptAction.showToast({ message: $r('app.string.clipboard_empty'), duration: 2000 });
      if (!this.inputExpanded) {
        this.expandInputArea();
      }
    }
  }

  /** 由 PasteButton 安全控件授权后读取剪贴板（无需 READ_PASTEBOARD） */
  private readClipboardAfterPasteButton(): void {
    pasteboard.getSystemPasteboard().getData((err: BusinessError, pasteData: pasteboard.PasteData) => {
      if (err) {
        promptAction.showToast({ message: '读取剪贴板失败', duration: 2000 });
        return;
      }
      const text = pasteData.getPrimaryText() ?? '';
      this.applyPastedText(text);
    });
  }

  private onPasteButtonClick(_event: ClickEvent, result: PasteButtonOnClickResult): void {
    if (this.interactionLocked) {
      return;
    }
    if (this.hasInputText()) {
      this.clearInputAndPrepareNewEntry();
      return;
    }
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      return;
    }
    this.readClipboardAfterPasteButton();
  }

  private copyInputToClipboard(): void {
    if (this.interactionLocked) {
      return;
    }
    if (this.inputText.length === 0) {
      promptAction.showToast({ message: $r('app.string.clipboard_empty'), duration: 2000 });
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.inputText);
      pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: $r('app.string.copy_done'), duration: 1500 });
    } catch (_err) {
      promptAction.showToast({ message: '复制失败', duration: 2000 });
    }
  }

  private sourceLangLabel(): string {
    return TranslateLanguages.labelForNllbCode(this.sourceNllbCode);
  }

  private targetLangLabel(): string {
    return TranslateLanguages.labelForNllbCode(this.targetNllbCode);
  }

  private sourceLangBarLabel(): string {
    return TranslateLanguages.compactLabelForLangBar(this.sourceLangLabel());
  }

  private targetLangBarLabel(): string {
    return TranslateLanguages.compactLabelForLangBar(this.targetLangLabel());
  }

  private openLanguagePicker(side: 'from' | 'to'): void {
    if (this.interactionLocked) {
      return;
    }
    this.langPickerForDetectedSource = false;
    this.langPickerSide = side;
    this.langPickerTitle = side === 'from' ? '原文语言' : '翻译成';
    this.langPickerVisible = true;
  }

  private onLanguagePicked(option: TranslateLanguageOption): void {
    if (this.langPickerForDetectedSource) {
      this.userOverrideSourceIso = option.isoCode;
      this.overrideBoundText = this.normalizedInput();
      this.langPickerVisible = false;
      this.langPickerForDetectedSource = false;
      this.activePlanSourceIso = '';
      this.updateSourceLanguageChipUi();
      this.refreshDisplayedSourceLangLabel();
      this.updatePasteAndConfirmVisibility();
      if (this.hasInputText()) {
        this.confirmTranslateFromInput();
      }
      return;
    }
    if (this.langPickerSide === 'from') {
      this.sourceNllbCode = option.nllbCode;
    } else {
      this.targetNllbCode = option.nllbCode;
    }
    this.refreshPairLangChoices();
    this.clearTranslationUi();
    this.refreshDisplayedSourceLangLabel();
    this.langPickerVisible = false;
  }

  private dismissLanguagePicker(): void {
    this.langPickerVisible = false;
    this.langPickerForDetectedSource = false;
  }

  private swapLanguages(): void {
    if (this.interactionLocked) {
      return;
    }
    const tmpCode = this.sourceNllbCode;
    this.sourceNllbCode = this.targetNllbCode;
    this.targetNllbCode = tmpCode;
    this.langPairRevision++;
    this.userOverrideSourceIso = null;
    this.overrideBoundText = null;
    this.refreshPairLangChoices();
    this.clearTranslationUi();
    this.updateSourceLanguageChipUi();
    this.refreshDisplayedSourceLangLabel();
    this.updatePasteAndConfirmVisibility();
  }

  private openSettings(): void {
    if (this.interactionLocked) {
      return;
    }
    router.pushUrl({ url: 'pages/Settings' });
  }

  /** 华为文档：cameraPicker 须在 UIAbility 上下文调用，优先 getContext(this) */
  private getUiAbilityContext(): common.UIAbilityContext | undefined {
    try {
      return getContext(this) as common.UIAbilityContext;
    } catch (_e) {
      return undefined;
    }
  }

  private toastByResName(resName: string, duration: number = 2500): void {
    if (resName.length === 0) {
      return;
    }
    if (resName === 'camera_permission_denied') {
      promptAction.showToast({ message: $r('app.string.camera_permission_denied'), duration });
    } else if (resName === 'camera_open_failed') {
      promptAction.showToast({ message: $r('app.string.camera_open_failed'), duration });
    } else if (resName === 'camera_unavailable') {
      promptAction.showToast({ message: $r('app.string.camera_unavailable'), duration });
    } else if (resName === 'album_open_failed') {
      promptAction.showToast({ message: $r('app.string.album_open_failed'), duration });
    }
  }

  private async navigateCameraTranslateWithUri(uri: string): Promise<void> {
    const targetIso = TranslateLanguages.isoForNllbCode(this.targetNllbCode);
    router.pushUrl({
      url: 'pages/CameraTranslate',
      params: {
        photoUri: uri,
        targetLang: targetIso,
      },
    });
  }

  private async openCameraTranslate(): Promise<void> {
    if (this.interactionLocked) {
      return;
    }
    const hostCtx = this.getUiAbilityContext();
    if (hostCtx === undefined) {
      promptAction.showToast({ message: $r('app.string.camera_open_failed'), duration: 2500 });
      return;
    }
    const outcome = await CameraLaunch.takePhoto(hostCtx);
    if (outcome.messageRes.length > 0) {
      this.toastByResName(outcome.messageRes);
    }
    if (outcome.uri === null || outcome.uri.length === 0) {
      return;
    }
    await this.navigateCameraTranslateWithUri(outcome.uri);
  }

  private async openAlbumTranslate(): Promise<void> {
    if (this.interactionLocked) {
      return;
    }
    const hostCtx = this.getUiAbilityContext();
    if (hostCtx === undefined) {
      promptAction.showToast({ message: $r('app.string.album_open_failed'), duration: 2500 });
      return;
    }
    const outcome = await CameraLaunch.pickFromAlbum(hostCtx);
    if (outcome.messageRes.length > 0) {
      this.toastByResName(outcome.messageRes);
    }
    if (outcome.uri === null || outcome.uri.length === 0) {
      return;
    }
    await this.navigateCameraTranslateWithUri(outcome.uri);
  }

  private prefSourceIso(): string {
    return TranslateLanguages.isoForNllbCode(this.sourceNllbCode);
  }

  private prefTargetIso(): string {
    return TranslateLanguages.isoForNllbCode(this.targetNllbCode);
  }

  private refreshPairLangChoices(): void {
    this.pairLangChoices = TranslateLanguages.getPairLanguageChoices(
      this.sourceNllbCode,
      this.targetNllbCode
    );
  }

  /** 仅在底栏选中的两种语言之间推断源语（对齐 Android 双向互译，不出现第三语种） */
  private detectSourceIsoForPair(text: string): string {
    return InputLanguageDetector.detectForHomePair(text, this.prefSourceIso(), this.prefTargetIso());
  }

  private normalizedInput(): string {
    return Index.normalizeInputNewlines(this.inputText);
  }

  private static normalizeInputNewlines(raw: string): string {
    return raw.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  private buildTranslationCacheKey(source: string): string {
    return `${this.langPairRevision}|${source.trim()}`;
  }

  /** 当前输入将按哪种源语翻译（自动识别或手动纠正，非底栏左侧固定中文） */
  private effectiveInputSourceIso(): string {
    const body = this.normalizedInput().trim();
    if (body.length === 0) {
      return this.prefSourceIso();
    }
    if (this.userOverrideSourceIso !== null) {
      return this.userOverrideSourceIso;
    }
    return this.detectSourceIsoForPair(body);
  }

  /** 源语言纠正弹窗默认选中项 */
  private pickerInitialSourceIso(): string {
    if (this.userOverrideSourceIso !== null) {
      return this.userOverrideSourceIso;
    }
    if (this.activePlanSourceIso.length > 0) {
      return this.activePlanSourceIso;
    }
    return this.detectSourceIsoForPair(this.normalizedInput());
  }

  private hasInputText(): boolean {
    return this.normalizedInput().trim().length > 0;
  }

  private refreshDisplayedSourceLangLabel(): void {
    if (!this.inputExpanded && !this.translationBlockVisible) {
      this.displayedSourceLangLabel = this.sourceLangLabel();
      return;
    }
    if (this.translationBlockVisible && this.activePlanSourceIso.length > 0) {
      this.displayedSourceLangLabel = TranslateLanguages.labelForIsoCode(this.activePlanSourceIso);
      return;
    }
    if (this.inputExpanded && this.hasInputText()) {
      this.displayedSourceLangLabel = TranslateLanguages.labelForIsoCode(this.effectiveInputSourceIso());
      return;
    }
    this.displayedSourceLangLabel = this.sourceLangLabel();
  }

  private updateSourceLanguageChipUi(): void {
    const body = this.normalizedInput();
    if (!this.inputExpanded || body.trim().length === 0) {
      this.showSourceLangChip = false;
      return;
    }
    this.showSourceLangChip = true;
    const preview = this.userOverrideSourceIso ?? this.detectSourceIsoForPair(body);
    const label = TranslateLanguages.labelForIsoCode(preview);
    if (this.userOverrideSourceIso !== null) {
      this.sourceLangChipText = `源语言 · ${label}（已指定）· 轻触重选`;
    } else {
      this.sourceLangChipText = `源语言 · ${label}（自动）· 轻触更正`;
    }
  }

  private updatePasteAndConfirmVisibility(): void {
    const has = this.hasInputText();
    const busy = this.translateInFlight || this.typewriterActive;
    const needsNew =
      this.lastSuccessfulTranslationKey === null ||
      this.buildTranslationCacheKey(this.normalizedInput()) !== this.lastSuccessfulTranslationKey;
    this.showConfirmTranslate = this.inputExpanded && has && !busy && needsNew;
  }

  private onInputTextChanged(next: string): void {
    const normalized = Index.normalizeInputNewlines(next);
    if (this.overrideBoundText !== null && normalized !== this.overrideBoundText) {
      this.userOverrideSourceIso = null;
      this.overrideBoundText = null;
    }
    if (this.lastSuccessfulTranslationKey !== null &&
      this.buildTranslationCacheKey(normalized) !== this.lastSuccessfulTranslationKey) {
      this.clearTranslationUi();
    }
    this.inputText = normalized;
    this.updateSourceLanguageChipUi();
    this.refreshDisplayedSourceLangLabel();
    this.updatePasteAndConfirmVisibility();
  }

  private clearTranslationUi(): void {
    this.cancelTypewriter();
    this.translateInFlight = false;
    this.lastSuccessfulTranslationKey = null;
    this.translationBlockVisible = false;
    this.translationProgressVisible = false;
    this.translationRows = [];
    this.primaryResultText = '';
    this.primaryResultLabel = '';
    this.primaryResultTargetIso = '';
    this.primaryResultShowActions = false;
    this.userOverrideSourceIso = null;
    this.overrideBoundText = null;
    this.lastAutoDetectedIso = null;
    this.lastUsedSourceIso = null;
    this.activePlanSourceIso = '';
    this.refreshDisplayedSourceLangLabel();
    this.updatePasteAndConfirmVisibility();
  }

  private openDetectedSourceLanguagePicker(): void {
    if (this.interactionLocked || !this.hasInputText()) {
      return;
    }
    this.refreshPairLangChoices();
    this.langPickerForDetectedSource = true;
    this.langPickerTitle = '源语言';
    const initialIso = this.pickerInitialSourceIso();
    this.langPickerSide = TranslateLanguages.nllbForIsoCode(initialIso);
    this.langPickerVisible = true;
  }

  private confirmTranslateFromInput(): void {
    if (this.translateInFlight || this.typewriterActive) {
      return;
    }
    const text = this.normalizedInput();
    if (text.trim().length === 0) {
      return;
    }
    if (this.prefSourceIso() === this.prefTargetIso()) {
      promptAction.showToast({ message: $r('app.string.same_source_target'), duration: 2000 });
      return;
    }
    void this.runTranslateJob(text);
  }

  private async runTranslateJob(sourceSnapshot: string): Promise<void> {
    if (this.translateInFlight) {
      return;
    }
    const normalized = Index.normalizeInputNewlines(sourceSnapshot);
    if (normalized.trim().length === 0) {
      return;
    }
    const prefsS = this.prefSourceIso();
    const prefsT = this.prefTargetIso();
    if (prefsS === prefsT) {
      return;
    }

    this.cancelTypewriter();
    this.translateInFlight = true;
    this.translationBlockVisible = true;
    this.translationProgressVisible = true;
    this.translationRows = [];
    this.primaryResultText = '';
    this.primaryResultLabel = '';
    this.primaryResultTargetIso = '';
    this.primaryResultShowActions = false;
    this.updatePasteAndConfirmVisibility();

    const translateBody = normalized.trim();
    const autoDetected = this.detectSourceIsoForPair(translateBody);
    const fromLang = this.userOverrideSourceIso ?? autoDetected;
    const plan = HomeTranslatePlanner.build(fromLang, prefsS, prefsT);
    const sourceKey = this.buildTranslationCacheKey(normalized);

    if (plan === null) {
      this.translateInFlight = false;
      this.translationBlockVisible = false;
      this.translationProgressVisible = false;
      this.updatePasteAndConfirmVisibility();
      return;
    }

    try {
      if (plan.kind === HomeTranslatePlanKind.SINGLE) {
        const result = await OnDeviceTranslator.translate(translateBody, plan.sourceIso, plan.targetIso);
        const outSingle = new TranslateOutputItem();
        outSingle.targetIso = plan.targetIso;
        outSingle.text = result;
        this.applyTranslateSuccess(plan, autoDetected, sourceKey, [outSingle]);
      } else {
        const r1 = await OnDeviceTranslator.translate(translateBody, plan.fromIso, plan.targetFirstIso);
        const r2 = await OnDeviceTranslator.translate(translateBody, plan.fromIso, plan.targetSecondIso);
        const out1 = new TranslateOutputItem();
        out1.targetIso = plan.targetFirstIso;
        out1.text = r1;
        const out2 = new TranslateOutputItem();
        out2.targetIso = plan.targetSecondIso;
        out2.text = r2;
        this.applyTranslateSuccess(plan, autoDetected, sourceKey, [out1, out2]);
      }
    } catch (e) {
      this.translateInFlight = false;
      this.translationBlockVisible = false;
      this.translationProgressVisible = false;
      this.translationRows = [];
      this.primaryResultText = '';
      this.primaryResultLabel = '';
      this.primaryResultTargetIso = '';
      this.primaryResultShowActions = false;
      this.cancelTypewriter();
      this.updatePasteAndConfirmVisibility();
      const err = e as Error;
      let msg: string | Resource = $r('app.string.translate_model_not_ready');
      const raw = err.message ?? '';
      if (raw.includes('429') || raw.includes('过于频繁')) {
        msg = $r('app.string.translate_rate_limit');
      } else if (raw.includes('MODEL_NOT_READY')) {
        if (raw.includes('未链接本机翻译库')) {
          msg = $r('app.string.translate_ct2_not_linked');
        } else if (raw.includes('正在加载')) {
          msg = $r('app.string.translate_model_loading');
        } else if (raw.includes('正在准备') || raw.includes('正在安装') || raw.includes('安装未完成')) {
          msg = $r('app.string.translate_model_installing');
        } else if (raw.includes('本机翻译引擎加载失败') || raw.includes('本机翻译引擎推理失败')) {
          const colon = raw.indexOf(':');
          if (colon >= 0 && raw.length - colon - 1 < 120) {
            msg = raw.substring(colon + 1).trim();
          } else {
            msg = $r('app.string.translate_offline_failed');
          }
        } else if (raw.includes('本机翻译')) {
          msg = $r('app.string.translate_offline_failed');
        } else {
          msg = $r('app.string.translate_model_not_ready');
        }
      } else if (raw.length > 0 && raw.length < 160) {
        msg = raw;
      }
      promptAction.showToast({
        message: msg,
        duration: 3500
      });
    }
  }

  private applyTranslateSuccess(
    plan: HomeTranslatePlan,
    autoDetected: string,
    sourceKey: string,
    outputs: TranslateOutputItem[]
  ): void {
    this.translateInFlight = false;
    this.translationProgressVisible = false;
    this.lastSuccessfulTranslationKey = sourceKey;
    this.lastAutoDetectedIso = autoDetected;
    if (plan.kind === HomeTranslatePlanKind.SINGLE) {
      this.lastUsedSourceIso = plan.sourceIso;
    } else {
      this.lastUsedSourceIso = plan.fromIso;
    }
    this.updateSourceLangLabelForPlan(plan);
    this.updateSourceLanguageChipUi();

    if (outputs.length === 1) {
      this.translationRows = [];
      this.primaryResultLabel = TranslateLanguages.labelForIsoCode(outputs[0].targetIso);
      this.primaryResultTargetIso = outputs[0].targetIso;
      this.primaryResultText = '';
      this.primaryResultShowActions = false;
      this.startTypewriter(outputs[0].text);
    } else {
      const rows: TranslationResultRow[] = [];
      for (let i = 0; i < outputs.length; i++) {
        const row = new TranslationResultRow();
        row.targetLabel = TranslateLanguages.labelForIsoCode(outputs[i].targetIso);
        row.targetIso = outputs[i].targetIso;
        row.displayedText = outputs[i].text;
        row.showActions = true;
        rows.push(row);
      }
      this.translationRows = rows;
      this.primaryResultLabel = '';
      this.primaryResultTargetIso = '';
      this.primaryResultText = '';
      this.primaryResultShowActions = false;
      this.updatePasteAndConfirmVisibility();
    }
  }

  private updateSourceLangLabelForPlan(plan: HomeTranslatePlan): void {
    if (plan.kind === HomeTranslatePlanKind.SINGLE) {
      this.activePlanSourceIso = plan.sourceIso;
      this.displayedSourceLangLabel = TranslateLanguages.labelForIsoCode(plan.sourceIso);
      return;
    }
    this.activePlanSourceIso = plan.fromIso;
    this.displayedSourceLangLabel =
      `${TranslateLanguages.labelForDetectedCode(plan.fromIso)} · 对照译至所选语言`;
  }

  private cancelTypewriter(): void {
    if (this.twTimerId >= 0) {
      clearTimeout(this.twTimerId);
      this.twTimerId = -1;
    }
    this.typewriterActive = false;
  }

  private startTypewriter(full: string): void {
    this.cancelTypewriter();
    this.twFull = full;
    this.twIndex = 0;
    this.primaryResultText = '';
    this.typewriterActive = true;
    this.tickTypewriter();
  }

  private tickTypewriter(): void {
    if (!this.typewriterActive) {
      return;
    }
    if (this.twIndex >= this.twFull.length) {
      this.finishTypewriter();
      return;
    }
    const backlogStart = this.twFull.length - this.twIndex;
    let maxBurst = 1;
    if (backlogStart > 96) {
      maxBurst = 24;
    } else if (backlogStart > 48) {
      maxBurst = 12;
    } else if (backlogStart > 20) {
      maxBurst = 6;
    } else if (backlogStart > 6) {
      maxBurst = 2;
    }
    const end = Math.min(this.twIndex + maxBurst, this.twFull.length);
    this.twIndex = end;
    this.primaryResultText = this.twFull.substring(0, this.twIndex);

    if (this.twIndex >= this.twFull.length) {
      this.finishTypewriter();
      return;
    }
    const backlog = this.twFull.length - this.twIndex;
    let delayMs = 40;
    if (backlog > 48) {
      delayMs = 6;
    } else if (backlog > 16) {
      delayMs = 10;
    } else if (backlog > 4) {
      delayMs = 18;
    }
    this.twTimerId = setTimeout(() => {
      this.twTimerId = -1;
      this.tickTypewriter();
    }, delayMs) as number;
  }

  private finishTypewriter(): void {
    this.typewriterActive = false;
    this.primaryResultText = this.twFull;
    this.primaryResultShowActions = true;
    this.updatePasteAndConfirmVisibility();
  }

  private clearInputAndPrepareNewEntry(): void {
    this.clearTranslationUi();
    this.inputText = '';
    this.updateSourceLanguageChipUi();
    this.updatePasteAndConfirmVisibility();
    if (!this.inputExpanded) {
      this.expandInputArea();
    } else {
      this.requestInputFocus(true);
    }
  }

  private copyPlainText(text: string): void {
    if (text.trim().length === 0) {
      promptAction.showToast({ message: $r('app.string.clipboard_empty'), duration: 1500 });
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: $r('app.string.copy_done'), duration: 1500 });
    } catch (_e) {
      promptAction.showToast({ message: '复制失败', duration: 2000 });
    }
  }

  private speakLangForPrimaryResult(): string {
    if (this.primaryResultTargetIso.length > 0) {
      return this.primaryResultTargetIso;
    }
    return this.prefTargetIso();
  }

  private speakLangForInput(): string {
    const body = this.normalizedInput();
    if (body.trim().length > 0) {
      return this.detectSourceIsoForPair(body);
    }
    if (this.activePlanSourceIso.length > 0) {
      return this.activePlanSourceIso;
    }
    return this.prefSourceIso();
  }

  private openTtsVoicePackPage(): void {
    router.pushUrl({ url: 'pages/TtsVoicePack' });
  }

  private speakTextForSlot(slotId: string, displayed: string): string {
    if (slotId === 'primary' && this.typewriterActive && this.twFull.length > displayed.length) {
      return this.twFull;
    }
    return displayed;
  }

  private async speakText(text: string, langIso: string, slotId: string): Promise<void> {
    const body = this.speakTextForSlot(slotId, text).trim();
    if (body.length === 0) {
      return;
    }
    const phase = TtsSpeakUi.getPhase();
    if (TtsSpeakUi.isSlotActive(slotId) &&
      (phase === TtsSpeakPhase.PLAYING || phase === TtsSpeakPhase.LOADING)) {
      await SileroTtsEngine.stop();
      TtsSpeakUi.setIdle();
      return;
    }
    if (phase !== TtsSpeakPhase.IDLE) {
      await SileroTtsEngine.stop();
      TtsSpeakUi.setIdle();
    }
    const iso = TtsVoiceCatalog.normalizeSpeakIso(langIso);
    if (!SileroTtsEngine.isSupportedLang(iso)) {
      promptAction.showToast({ message: $r('app.string.speak_lang_not_supported'), duration: 2000 });
      return;
    }
    if (!SileroTtsEngine.isReady()) {
      promptAction.showToast({ message: $r('app.string.speak_not_ready'), duration: 2000 });
      return;
    }
    TtsSpeakUi.setLoading(slotId);
    let ok = false;
    try {
      ok = await SileroTtsEngine.speak(body, iso, {
        onPlaybackStart: () => {
          if (TtsSpeakUi.isSlotActive(slotId) && TtsSpeakUi.getPhase() === TtsSpeakPhase.LOADING) {
            TtsSpeakUi.setPlaying(slotId);
          }
        }
      });
    } finally {
      if (TtsSpeakUi.isSlotActive(slotId)) {
        TtsSpeakUi.setIdle();
      }
    }
    if (!ok) {
      const failure = SileroTtsEngine.getLastSpeakFailure();
      if (failure === SileroSpeakFailure.MODEL_MISSING || failure === SileroSpeakFailure.MOBILE_MODEL_MISSING) {
        let noModelMsg: string | Resource = $r('app.string.tts_speak_no_model');
        if (iso === 'ru') {
          noModelMsg = '请先打开「朗读语言」安装俄语包';
        } else if (iso === 'pl') {
          noModelMsg = '请先打开「朗读语言」安装波兰语包';
        } else if (iso === 'pt') {
          noModelMsg = '请先打开「朗读语言」安装葡萄牙语包';
        } else if (iso === 'ka') {
          noModelMsg = '请先打开「朗读语言」安装格鲁吉亚语包';
        } else if (iso === 'de') {
          noModelMsg = '请先打开「朗读语言」安装德语包';
        } else if (iso === 'da') {
          noModelMsg = '请先打开「朗读语言」安装丹麦语包';
        } else if (iso === 'el') {
          noModelMsg = '请先打开「朗读语言」安装希腊语包';
        } else if (iso === 'fa') {
          noModelMsg = '请先打开「朗读语言」安装波斯语包';
        } else if (iso === 'fi') {
          noModelMsg = '请先打开「朗读语言」安装芬兰语包';
        } else if (iso === 'cy') {
          noModelMsg = '请先打开「朗读语言」安装威尔士语包';
        } else if (iso === 'fr') {
          noModelMsg = '请先打开「朗读语言」安装法语包';
        } else if (iso === 'hi') {
          noModelMsg = '请先打开「朗读语言」安装印地语包';
        } else if (iso === 'hu') {
          noModelMsg = '请先打开「朗读语言」安装匈牙利语包';
        } else if (iso === 'is') {
          noModelMsg = '请先打开「朗读语言」安装冰岛语包';
        } else if (iso === 'it') {
          noModelMsg = '请先打开「朗读语言」安装意大利语包';
        } else if (iso === 'kk') {
          noModelMsg = '请先打开「朗读语言」安装哈萨克语包';
        } else if (iso === 'lb') {
          noModelMsg = '请先打开「朗读语言」安装卢森堡语包';
        } else if (iso === 'lv') {
          noModelMsg = '请先打开「朗读语言」安装拉脱维亚语包';
        } else if (iso === 'ml') {
          noModelMsg = '请先打开「朗读语言」安装马拉雅拉姆语包';
        } else if (iso === 'ne') {
          noModelMsg = '请先打开「朗读语言」安装尼泊尔语包';
        } else if (iso === 'nl') {
          noModelMsg = '请先打开「朗读语言」安装荷兰语包';
        } else if (iso === 'no') {
          noModelMsg = '请先打开「朗读语言」安装挪威语包';
        } else if (iso === 'ro') {
          noModelMsg = '请先打开「朗读语言」安装罗马尼亚语包';
        } else if (iso === 'sk') {
          noModelMsg = '请先打开「朗读语言」安装斯洛伐克语包';
        } else if (iso === 'sl') {
          noModelMsg = '请先打开「朗读语言」安装斯洛文尼亚语包';
        } else if (iso === 'sr') {
          noModelMsg = '请先打开「朗读语言」安装塞尔维亚语包';
        } else if (iso === 'sv') {
          noModelMsg = '请先打开「朗读语言」安装瑞典语包';
        } else if (iso === 'sw') {
          noModelMsg = '请先打开「朗读语言」安装斯瓦希里语包';
        } else if (iso === 'tr') {
          noModelMsg = '请先打开「朗读语言」安装土耳其语包';
        } else if (iso === 'vi') {
          noModelMsg = '请先打开「朗读语言」安装越南语包';
        }
        promptAction.showToast({ message: noModelMsg, duration: 2500 });
      } else if (failure === SileroSpeakFailure.ENGINE_NOT_LINKED) {
        let msg: ResourceStr = $r('app.string.tts_speak_engine_not_linked');
        if (SileroTtsNative.isX86EmulatorStub()) {
          msg = $r('app.string.tts_speak_emulator_stub');
        } else if (iso === 'ja' && !SileroTtsNative.usesPiperPlus()) {
          msg = `朗读失败(${iso})：当前架构未编入 piper-plus，请运行 prepare_native_tts.ps1 后 Clean 重编`;
        } else if (iso === 'zh' && !SileroTtsNative.usesSummerTts()) {
          msg = `朗读失败(${iso})：当前 HAP 未编入 SummerTTS，请 Clean 重编后重装`;
        } else {
          msg = `朗读失败(${iso})：${msg}`;
        }
        promptAction.showToast({ message: msg, duration: 5000 });
      } else if (failure === SileroSpeakFailure.PLAYBACK_FAILED) {
        promptAction.showToast({
          message: '朗读失败：音频播放异常，请调高媒体音量后重试',
          duration: 3000
        });
      } else if (failure === SileroSpeakFailure.SYNTHESIZE_FAILED) {
        const detail = SileroTtsEngine.getLastSynthesizeError();
        const speakIso = iso;
        let hint: string = '';
        if (detail.indexOf('SummerTTS') >= 0 || detail.indexOf('single_speaker_fast') >= 0) {
          hint = '中文：请到「朗读语言」安装中文语音包';
        } else if (detail.indexOf('piper') >= 0 || detail.indexOf('OpenJTalk') >= 0) {
          const piperEntry = TtsVoiceCatalog.findByIso(speakIso);
          if (speakIso === 'ja' || detail.indexOf('OpenJTalk') >= 0) {
            hint = '日语：请安装日语包；开发机运行 prepare_native_tts.ps1 后重编';
          } else if (piperEntry?.engine === 'piper') {
            hint = `${piperEntry.label}：请到「朗读语言」安装 Piper 语音包`;
          } else {
            hint = '请到「朗读语言」安装 Piper 语音包';
          }
        } else if (detail.indexOf('Unsupported TTS language') >= 0) {
          hint = '该语种朗读引擎尚未接入';
        } else if (detail.indexOf('PyTorch') >= 0 || detail.indexOf('pytorch') >= 0) {
          hint = '请编入 libpytorch_ohos.so 后 Clean 重编（见 build_silero_tts_ohos.md）';
        } else if (detail.indexOf('not installed') >= 0 || detail.indexOf('model not') >= 0) {
          const entry = TtsVoiceCatalog.findByIso(speakIso);
          hint = entry !== undefined
            ? `「朗读语言」里安装 ${entry.label} 对应语音包`
            : `「朗读语言」里安装 ${speakIso} 对应语音包`;
        } else if (detail.length > 0 && detail.length < 160) {
          hint = detail;
        }
        promptAction.showToast({
          message: hint.length > 0 ? `朗读失败(${speakIso})：${hint}` : $r('app.string.tts_speak_failed'),
          duration: 3500
        });
      } else {
        promptAction.showToast({ message: $r('app.string.tts_speak_failed'), duration: 2500 });
      }
    }
  }

  private reopenInputFromResultTap(): void {
    if (this.interactionLocked) {
      return;
    }
    if (!this.inputExpanded) {
      this.expandInputArea();
      return;
    }
    this.requestInputFocus(false);
  }

  @Builder
  InteractionBlocker() {
    if (this.interactionLocked) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Block)
        .zIndex(1000)
    }
  }

  @Builder
  PasteOrClearChip() {
    if (this.hasInputText()) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(16)
          .fontColor([$r('app.color.ui_text_primary')])
        Text($r('app.string.clear_input'))
          .fontSize(13)
          .fontColor($r('app.color.ui_text_primary'))
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.ui_paste_chip_bg'))
      .borderRadius(20)
      .onClick(() => {
        this.clearInputAndPrepareNewEntry();
      })
    } else {
      // 仅用系统 PasteButton（自带图标+「粘贴」），勿再包一层自定义文案，否则会显示两个「粘贴」
      PasteButton()
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(20)
        .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
          this.onPasteButtonClick(event, result);
        })
    }
  }

  @Builder
  ConfirmTranslateChip() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(16)
        .fontColor([$r('app.color.ui_text_primary')])
      Text($r('app.string.confirm_translate'))
        .fontSize(13)
        .fontColor($r('app.color.ui_text_primary'))
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.ui_paste_chip_bg'))
    .borderRadius(20)
    .onClick(() => {
      this.confirmTranslateFromInput();
    })
  }

  @Builder
  SourceLangDetectChip() {
    Text(this.sourceLangChipText)
      .fontSize(13)
      .fontColor($r('app.color.ui_text_primary'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.ui_paste_chip_bg'))
      .borderRadius(20)
      .margin({ left: INPUT_CONTENT_PAD_H, right: INPUT_CONTENT_PAD_H, bottom: 8 })
      .onClick(() => {
        this.openDetectedSourceLanguagePicker();
      })
  }

  @Builder
  TranslationResultBlock() {
    if (this.translationBlockVisible) {
      Column() {
        if (this.translationProgressVisible) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.ui_text_primary'))
            .margin({ top: 10, bottom: 8 })
        }
        if (this.primaryResultLabel.length > 0) {
          Column() {
            Text(this.primaryResultLabel)
              .fontSize(14)
              .fontColor($r('app.color.ui_input_hint'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 4 })
            Text(this.primaryResultText)
              .fontSize(24)
              .fontColor($r('app.color.ui_text_primary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 4 })
            if (this.primaryResultShowActions) {
              Row() {
                SpeakActionButton({
                  slotId: 'primary',
                  onSpeak: () => {
                    void this.speakText(this.primaryResultText, this.speakLangForPrimaryResult(), 'primary');
                  },
                  onOpenVoicePack: () => {
                    this.openTtsVoicePackPage();
                  }
                })
                Blank().layoutWeight(1)
                SymbolHeaderButton({
                  symbol: $r('sys.symbol.square_on_square_fill'),
                  onAction: () => {
                    this.copyPlainText(this.primaryResultText);
                  }
                })
              }
              .width('100%')
              .padding({ top: 6 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        ForEach(this.translationRows, (row: TranslationResultRow, index: number) => {
          Column() {
            Text(row.targetLabel)
              .fontSize(14)
              .fontColor($r('app.color.ui_input_hint'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: index === 0 ? 4 : 12 })
            Text(row.displayedText)
              .fontSize(24)
              .fontColor($r('app.color.ui_text_primary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 4 })
            if (row.showActions) {
              Row() {
                SpeakActionButton({
                  slotId: `row_${index}`,
                  onSpeak: () => {
                    void this.speakText(row.displayedText, row.targetIso, `row_${index}`);
                  },
                  onOpenVoicePack: () => {
                    this.openTtsVoicePackPage();
                  }
                })
                Blank().layoutWeight(1)
                SymbolHeaderButton({
                  symbol: $r('sys.symbol.square_on_square_fill'),
                  onAction: () => {
                    this.copyPlainText(row.displayedText);
                  }
                })
              }
              .width('100%')
              .padding({ top: 6 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (row: TranslationResultRow, index: number) =>
        `${index}_${row.targetLabel}_${row.displayedText.length}`)
      }
      .width('100%')
      .padding({
        left: INPUT_CONTENT_PAD_H,
        right: INPUT_CONTENT_PAD_H,
        top: 12
      })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.reopenInputFromResultTap();
      })
    }
  }

  /**
   * 须在 @Builder 内直接读 this.sourceLangLabel()，勿把文案当 string 参数传入。
   * @Builder 默认按值传参，传入的 label 不会随 @State 刷新（见华为 @Builder 参数传递说明）。
   */
  @Builder
  LangTile(side: 'from' | 'to', onTap: () => void) {
    Text(side === 'from' ? this.sourceLangBarLabel() : this.targetLangBarLabel())
      .width('100%')
      .fontSize(15)
      .fontColor($r('app.color.ui_text_primary'))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minHeight: 52 })
      .padding({ left: 12, right: 12, top: 14, bottom: 14 })
      .backgroundColor($r('app.color.ui_ime_lang_pill'))
      .border({
        width: 1,
        color: $r('app.color.ui_ime_lang_pill_stroke')
      })
      .borderRadius(14)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  KeyboardLangBar() {
    Row() {
      Text(this.sourceLangBarLabel())
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.ui_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.ui_ime_lang_pill'))
        .border({
          width: 1,
          color: $r('app.color.ui_ime_lang_pill_stroke')
        })
        .borderRadius(14)
        .onClick(() => {
          this.openLanguagePicker('from');
        })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
          .fontSize(22)
          .fontColor([$r('app.color.ui_text_primary')])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .margin({ left: 6, right: 6 })
      .onClick(() => this.swapLanguages())

      Text(this.targetLangBarLabel())
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.ui_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.ui_ime_lang_pill'))
        .border({
          width: 1,
          color: $r('app.color.ui_ime_lang_pill_stroke')
        })
        .borderRadius(14)
        .onClick(() => {
          this.openLanguagePicker('to');
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.ui_ime_toolbar_sheet'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  /** Android bottomStrip：peek 高度内内容 layout_gravity=bottom 贴底 */
  @Builder
  BottomHomeStripContent() {
    Column() {
      Row() {
        Column() {
          this.LangTile('from', () => {
            this.openLanguagePicker('from');
          })
        }
        .layoutWeight(1)
        .clip(true)
        .margin({ left: 4 })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(22)
            .fontColor([$r('app.color.ui_text_primary')])
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .margin({ left: 6, right: 6 })
        .onClick(() => this.swapLanguages())

        Column() {
          this.LangTile('to', () => {
            this.openLanguagePicker('to');
          })
        }
        .layoutWeight(1)
        .clip(true)
        .margin({ right: 4 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 14 })

      Row() {
        ImmersiveLightIconButton({
          symbol: $r('sys.symbol.gearshape'),
          buttonSize: 52,
          iconSize: 22,
          onAction: () => this.openSettings()
        })
        Blank().width(28)
        ImmersiveLightIconButton({
          symbol: $r('sys.symbol.camera'),
          buttonSize: 64,
          iconSize: 28,
          onAction: () => {
            this.openCameraTranslate();
          },
          onLongPress: () => {
            this.openAlbumTranslate();
          }
        })
        Blank().width(28)
        ImmersiveLightIconButton({
          symbol: $r('sys.symbol.arrow_counterclockwise_clock'),
          buttonSize: 52,
          iconSize: 22,
          onAction: () => {
            if (!this.interactionLocked) {
              promptAction.showToast({ message: '历史记录', duration: 1500 });
            }
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14, bottom: 6 })
    }
    .width('100%')
    .padding({ bottom: 4 + this.navBarBottomInsetVp })
  }

  @Builder
  BottomSheetPeek() {
    Column() {
      Blank().layoutWeight(1)
      Column() {
        this.BottomHomeStripContent()
      }
      .width('100%')
      .opacity(this.bottomStripOpacity)
      .key(`${this.sourceNllbCode}|${this.targetNllbCode}`)
    }
    .width('100%')
    .height(this.stripPeekHeightVp)
    .justifyContent(FlexAlign.End)
    .backgroundColor($r('app.color.ui_ime_toolbar_bg'))
  }

  @Builder
  BlackInputHost() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (!this.inputExpanded) {
          Text($r('app.string.EntryAbility_label'))
            .fontSize(18)
            .fontColor($r('app.color.ui_text_primary'))
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 8 })
            .opacity(this.homeTitleOpacity)
            .onClick(() => {
              if (!this.interactionLocked) {
                this.expandInputArea();
              }
            })
        }

        if (this.inputExpanded) {
          Row() {
            SymbolHeaderButton({
              symbol: $r('sys.symbol.chevron_left'),
              iconSize: 24,
              onAction: () => this.handleBackPress()
            })
            Blank().layoutWeight(1)
            SymbolHeaderButton({
              symbol: $r('sys.symbol.arrow_counterclockwise_clock'),
              onAction: () => {
                if (!this.interactionLocked) {
                  promptAction.showToast({ message: '历史记录', duration: 1500 });
                }
              }
            })
            SymbolHeaderButton({
              symbol: $r('sys.symbol.square_on_square_fill'),
              onAction: () => this.copyInputToClipboard()
            })
            SpeakActionButton({
              slotId: 'input',
              actionEnabled: !this.interactionLocked,
              onSpeak: () => {
                void this.speakText(this.normalizedInput(), this.speakLangForInput(), 'input');
              },
              onOpenVoicePack: () => {
                this.openTtsVoicePackPage();
              }
            })
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 4, bottom: 4 })

          Text(this.displayedSourceLangLabel)
            .fontSize(14)
            .fontColor($r('app.color.ui_input_hint'))
            .width('100%')
            .padding({ left: INPUT_CONTENT_PAD_H, top: 4 })
        }

        if (this.showSourceLangChip && this.inputExpanded) {
          this.SourceLangDetectChip()
        }

        Scroll() {
          Column() {
            TextArea({
              text: this.inputText,
              placeholder: $r('app.string.input_placeholder'),
              controller: this.textAreaController
            })
              .id('mainInputArea')
              .fontSize(24)
              .fontColor($r('app.color.ui_text_primary'))
              .placeholderColor($r('app.color.ui_input_hint'))
              .backgroundColor(Color.Transparent)
              .width('100%')
              .constraintSize({ minHeight: 120 })
              .style(TextContentStyle.DEFAULT)
              .maxLines(9999)
              .barState(BarState.Off)
              .padding({
                left: INPUT_CONTENT_PAD_H,
                right: INPUT_CONTENT_PAD_H,
                top: 4,
                bottom: 8
              })
              .enableKeyboardOnFocus(this.inputExpanded)
              .focusable(this.inputExpanded)
              .onChange((value: string) => {
                if (value.length > this.inputText.length && value.charAt(value.length - 1) === '\n') {
                  const withoutEnter = value.substring(0, value.length - 1);
                  this.onInputTextChanged(withoutEnter);
                  this.confirmTranslateFromInput();
                  return;
                }
                this.onInputTextChanged(value);
              })
              .onClick(() => {
                this.onInputAreaTapped();
              })

            this.TranslationResultBlock()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: this.getInputScrollMinHeightVp() })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
        .onClick(() => {
          if (!this.inputExpanded && !this.interactionLocked) {
            this.expandInputArea();
          }
        })

        if (!this.inputExpanded) {
          Row() {
            this.PasteOrClearChip()
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 8 })
        }

        if (this.inputExpanded) {
          this.ExpandedBottomChrome()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarTopInsetVp })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (!this.inputExpanded && !this.interactionLocked) {
          this.expandInputArea();
        }
      })

      // Android sheetDragHandle：叠在黑区底边中央，不在输入框下方流式排版
      if (!this.inputExpanded) {
        Row() {
          Row()
            .width(36)
            .height(4)
            .backgroundColor($r('app.color.ui_handle_pill'))
            .borderRadius(2)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 12 })
        .onClick(() => {
          if (!this.interactionLocked) {
            this.expandInputArea();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_pure_black'))
    .borderRadius(this.inputExpanded ? 0 : {
      bottomLeft: PANEL_BOTTOM_RADIUS_VP,
      bottomRight: PANEL_BOTTOM_RADIUS_VP
    })
    .clip(true)
  }

  @Builder
  ExpandedBottomChrome() {
    Column() {
      Row() {
        this.PasteOrClearChip()
        Blank().layoutWeight(1)
        if (this.showConfirmTranslate) {
          this.ConfirmTranslateChip()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 10 })

      if (this.inputExpanded && (this.keyboardHeightVp > 0.5 || this.langBarOpacity > 0.01)) {
        Column() {
          this.KeyboardLangBar()
        }
        .width('100%')
        .opacity(this.langBarOpacity > 0.01 ? this.langBarOpacity : 1)
        .translate({ y: this.langBarTranslateYVp })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.ui_pure_black'))
  }

  build() {
    // 底栏叠层贴底；黑区用「视口高度 − margin」定高（等价 Android match_parent + bottomMargin）
    Stack({ alignContent: Alignment.TopStart }) {
      if (!this.inputExpanded) {
        Column() {
          this.BottomSheetPeek()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      Column() {
        this.BlackInputHost()
      }
      .width('100%')
      .height(this.getBlackHostLayoutHeightVp())
      .align(Alignment.TopStart)
      .clip(true)

      this.InteractionBlocker()

      LanguagePickerOverlay({
        visible: this.langPickerVisible,
        title: this.langPickerTitle,
        choices: this.langPickerForDetectedSource ? this.pairLangChoices : this.langChoices,
        selectedNllbCode: this.langPickerForDetectedSource
          ? this.langPickerSide
          : (this.langPickerSide === 'from' ? this.sourceNllbCode : this.targetNllbCode),
        onPick: (option: TranslateLanguageOption) => {
          this.onLanguagePicked(option);
        },
        onDismiss: () => {
          this.dismissLanguagePicker();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_ime_toolbar_bg'))
    .clip(false)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onAreaChange((_old, area: Area) => {
      const h = area.height as number;
      if (h > 0 && Math.abs(h - this.viewportHeightVp) > 0.5) {
        this.viewportHeightVp = h;
        if (!this.inputExpanded) {
          this.blackHostBottomMarginVp = this.computeCollapsedBottomMarginVp(this.keyboardHeightVp);
        }
      }
    })
  }
}
