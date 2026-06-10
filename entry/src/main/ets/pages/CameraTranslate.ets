import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { SymbolHeaderButton } from '../components/SymbolHeaderButton';
import { OcrLayoutStructure } from '../translation/OcrLayoutStructure';
import { OCR_UNAVAILABLE_CODE, OcrHelper } from '../translation/OcrHelper';
import { OcrMeta } from '../translation/OcrMeta';
import { OnDeviceTranslator } from '../translation/OnDeviceTranslator';
import { TextLanguageHeuristic } from '../translation/TextLanguageHeuristic';
import { TranslateLanguageOption, TranslateLanguages } from '../translation/TranslateLanguages';

const PHOTO_PREVIEW_H: number = 220;
const CARD_RADIUS: number = 32;
const PAGE_H_MARGIN: number = 16;
const EXPAND_MS: number = 380;
const COLLAPSE_MS: number = 320;

interface ExpandCardRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface ExpandedImageLayout {
  w: number;
  h: number;
  x: number;
  y: number;
}

@Entry
@Component
struct CameraTranslate {
  @State photoUri: string = '';
  @State targetLangIso: string = 'en';
  @State detectedLangIso: string = 'en';
  @State sourceLangLabel: string = '';
  @State targetLangLabel: string = '';
  @State ocrText: string = '';
  @State translatedText: string = '';
  @State ocrMetaSummary: string = '';
  @State ocrExpanded: boolean = false;
  @State loading: boolean = true;
  @State statusText: string = '正在识别…';
  @State resultVisible: boolean = false;
  @State bottomBarVisible: boolean = false;
  @State showTranslated: boolean = false;
  @State ocrHeaderVisible: boolean = false;
  @State targetPickerVisible: boolean = false;
  @State readyForTargetChange: boolean = false;
  @State photoExpanded: boolean = false;
  @State photoExpandProgress: number = 0;
  @State photoViewerAnimating: boolean = false;
  private closingPhotoExpand: boolean = false;
  @State thumbLeft: number = PAGE_H_MARGIN;
  @State thumbTop: number = 100;
  @State thumbWidth: number = 300;
  @State thumbHeight: number = PHOTO_PREVIEW_H;
  @State screenWidth: number = 360;
  @State screenHeight: number = 780;
  @State imagePixelW: number = 0;
  @State imagePixelH: number = 0;
  @State statusBarTopInsetVp: number = 0;
  @State navBarBottomInsetVp: number = 0;

  private layoutLines: string[] = [];
  private useLineMode: boolean = false;
  private avoidAreaListener: ((data: window.AvoidAreaOptions) => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.photoUri = params['photoUri'] ?? '';
    this.targetLangIso = params['targetLang'] ?? 'en';
    this.updateTargetLabel();
    const hostCtx = this.getUIContext().getHostContext();
    if (hostCtx) {
      TranslateLanguages.loadFromRawfile(hostCtx as common.UIAbilityContext);
      this.refreshSystemBarInsets(hostCtx as common.UIAbilityContext);
      window.getLastWindow(hostCtx).then((w: window.Window) => {
        this.avoidAreaListener = (data: window.AvoidAreaOptions) => {
          if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
            data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
            this.refreshSystemBarInsets(hostCtx as common.UIAbilityContext);
          }
        };
        w.on('avoidAreaChange', this.avoidAreaListener);
      }).catch(() => {
        // ignore
      });
    }
    if (this.photoUri.length === 0) {
      promptAction.showToast({ message: '未获取到照片', duration: 2000 });
      router.back();
      return;
    }
    this.loadImagePixelSize();
    this.runFullPipeline();
  }

  /** 相册 URI 须 fd 读尺寸（与 OcrHelper 一致），否则宽高为 0 会导致全屏始终 centerCrop */
  private async loadImagePixelSize(): Promise<void> {
    if (this.photoUri.length === 0) {
      return;
    }
    let opened: fileIo.File | undefined;
    try {
      try {
        opened = fileIo.openSync(this.photoUri, fileIo.OpenMode.READ_ONLY);
        const source = image.createImageSource(opened.fd);
        const info = await source.getImageInfo();
        this.imagePixelW = info.size.width;
        this.imagePixelH = info.size.height;
        source.release();
        return;
      } catch (_fdErr) {
        // 相机 saveUri 等可能可直接 createImageSource(uri)
      } finally {
        if (opened !== undefined) {
          try {
            fileIo.closeSync(opened);
          } catch (_closeErr) {
            // ignore
          }
          opened = undefined;
        }
      }
      const source = image.createImageSource(this.photoUri);
      const info = await source.getImageInfo();
      this.imagePixelW = info.size.width;
      this.imagePixelH = info.size.height;
      source.release();
    } catch (_e) {
      this.imagePixelW = 0;
      this.imagePixelH = 0;
    }
  }

  aboutToDisappear(): void {
    OcrHelper.release();
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (hostCtx !== undefined && this.avoidAreaListener !== null) {
      window.getLastWindow(hostCtx).then((w: window.Window) => {
        w.off('avoidAreaChange', this.avoidAreaListener!);
      }).catch(() => {
        // ignore
      });
    }
  }

  private refreshSystemBarInsets(hostCtx: common.UIAbilityContext): void {
    window.getLastWindow(hostCtx).then((w: window.Window) => {
      const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.statusBarTopInsetVp = this.getUIContext().px2vp(sys.topRect.height);
      this.navBarBottomInsetVp = this.getUIContext().px2vp(nav.bottomRect.height);
    }).catch(() => {
      // ignore
    });
  }

  onBackPress(): boolean {
    if (this.photoExpanded) {
      this.collapsePhotoExpand();
      return true;
    }
    router.back();
    return true;
  }

  private toastOcrError(e: object): void {
    const msg = (e as Error).message ?? '';
    if (msg === OCR_UNAVAILABLE_CODE) {
      promptAction.showToast({ message: $r('app.string.ocr_unavailable'), duration: 3500 });
    } else {
      promptAction.showToast({ message: msg.length > 0 ? msg : $r('app.string.ocr_failed'), duration: 2500 });
    }
  }

  private updateTargetLabel(): void {
    const choices = TranslateLanguages.getCameraTargetChoices();
    let label = this.targetLangIso.toUpperCase();
    for (let i = 0; i < choices.length; i++) {
      if (choices[i].isoCode === this.targetLangIso) {
        label = choices[i].label;
        break;
      }
    }
    this.targetLangLabel = label;
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  private async expandPhotoExpand(): Promise<void> {
    if (this.photoExpanded || this.photoViewerAnimating || this.thumbWidth <= 0) {
      return;
    }
    if (this.imagePixelW <= 0 || this.imagePixelH <= 0) {
      await this.loadImagePixelSize();
    }
    this.closingPhotoExpand = false;
    this.photoViewerAnimating = true;
    this.photoExpandProgress = 0;
    this.photoExpanded = true;
    animateTo({ duration: EXPAND_MS, curve: Curve.FastOutSlowIn }, () => {
      this.photoExpandProgress = 1;
    });
    setTimeout(() => {
      this.photoViewerAnimating = false;
    }, EXPAND_MS);
  }

  private collapsePhotoExpand(): void {
    if (!this.photoExpanded || this.photoViewerAnimating) {
      return;
    }
    this.closingPhotoExpand = true;
    this.photoViewerAnimating = true;
    animateTo({ duration: COLLAPSE_MS, curve: Curve.FastOutSlowIn }, () => {
      this.photoExpandProgress = 0;
    });
    setTimeout(() => {
      this.photoExpanded = false;
      this.photoViewerAnimating = false;
      this.closingPhotoExpand = false;
    }, COLLAPSE_MS);
  }

  /** 横图（宽>高）：展开时更快进入 fitCenter（上下留黑）；竖图与窗口同步完整动画 */
  private isLandscapePhoto(): boolean {
    return this.imagePixelW > this.imagePixelH;
  }

  private matrixFitProgress(cardT: number): number {
    if (cardT <= 0) {
      return 0;
    }
    if (cardT >= 1) {
      return 1;
    }
    if (!this.isLandscapePhoto()) {
      return cardT;
    }
    if (!this.closingPhotoExpand) {
      return Math.min(1, cardT * 1.75);
    }
    return Math.pow(cardT, 0.55);
  }

  /** 动画窗口矩形：从缩略图四边 lerp 到全屏（对齐 Android applyExpandedCardBounds） */
  private expandCardRect(): ExpandCardRect {
    const t = this.photoExpandProgress;
    const left = this.lerp(this.thumbLeft, 0, t);
    const top = this.lerp(this.thumbTop, 0, t);
    const right = this.lerp(this.thumbLeft + this.thumbWidth, this.screenWidth, t);
    const bottom = this.lerp(this.thumbTop + this.thumbHeight, this.screenHeight, t);
    return {
      left,
      top,
      width: Math.max(0, right - left),
      height: Math.max(0, bottom - top),
    };
  }

  private expandedRadius(): number {
    return this.lerp(CARD_RADIUS, 28, this.photoExpandProgress);
  }

  /**
   * 对齐 Android updateExpandedImageMatrix：progress=0 为 centerCrop，progress=1 为 fitCenter。
   * 收起时窗口缩小 + 缩放从 fit 回到 crop，避免长图先挤成中间细条再撑开。
   */
  private hasImagePixelSize(): boolean {
    return this.imagePixelW > 0 && this.imagePixelH > 0;
  }

  private expandedImageLayout(viewW: number, viewH: number): ExpandedImageLayout {
    const fitP = this.matrixFitProgress(this.photoExpandProgress);
    const dw = this.imagePixelW;
    const dh = this.imagePixelH;
    if (viewW <= 0 || viewH <= 0 || !this.hasImagePixelSize()) {
      return { w: 0, h: 0, x: 0, y: 0 };
    }
    const sCrop = Math.max(viewW / dw, viewH / dh);
    const sFit = Math.min(viewW / dw, viewH / dh);
    const s = sCrop * (1 - fitP) + sFit * fitP;
    const w = dw * s;
    const h = dh * s;
    const layout: ExpandedImageLayout = {
      w,
      h,
      x: (viewW - w) / 2,
      y: (viewH - h) / 2,
    };
    return layout;
  }

  private currentExpandedLayout(): ExpandedImageLayout {
    const rect = this.expandCardRect();
    return this.expandedImageLayout(rect.width, rect.height);
  }

  @Builder
  ExpandedPhotoLayer() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.ui_pure_black'))
      if (this.hasImagePixelSize()) {
        Stack() {
          Image(this.photoUri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        }
        .width(this.currentExpandedLayout().w)
        .height(this.currentExpandedLayout().h)
        .position({
          x: this.currentExpandedLayout().x,
          y: this.currentExpandedLayout().y,
        })
      } else {
        Image(this.photoUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      }
    }
    .width(this.expandCardRect().width)
    .height(this.expandCardRect().height)
    .position({
      x: this.expandCardRect().left,
      y: this.expandCardRect().top,
    })
    .borderRadius(this.expandedRadius())
    .clip(true)
    .backgroundColor($r('app.color.ui_pure_black'))
  }

  private async runFullPipeline(): Promise<void> {
    this.loading = true;
    this.resultVisible = false;
    this.bottomBarVisible = false;
    this.statusText = '正在检测语言…';
    try {
      const page = await OcrHelper.recognizeFromUri(this.photoUri);
      const sorted = page.lines;
      const layoutRows = OcrLayoutStructure.insertParagraphBlanks(sorted);
      const structuredText = layoutRows.length > 0 ? layoutRows.join('\n') : page.fullText;
      this.useLineMode = layoutRows.length > 0 && structuredText.length >= 8;
      this.layoutLines = this.useLineMode ? layoutRows : [];
      this.ocrText = structuredText.substring(0, 4000);
      if (this.ocrText.trim().length === 0) {
        this.loading = false;
        this.resultVisible = true;
        this.ocrHeaderVisible = false;
        this.showTranslated = false;
        this.ocrText = '未识别到文字'; // 展示用；资源见 no_text_detected
        return;
      }
      this.detectedLangIso = TextLanguageHeuristic.guessIsoCode(this.ocrText);
      this.sourceLangLabel = TranslateLanguages.labelForDetectedCode(this.detectedLangIso);
      this.ocrMetaSummary = OcrMeta.summaryLine(this.detectedLangIso, this.ocrText);
      this.statusText = '正在翻译…';
      let translated = '';
      if (this.useLineMode) {
        const outs = await OnDeviceTranslator.translateLines(
          this.layoutLines,
          this.detectedLangIso,
          this.targetLangIso,
        );
        translated = outs.join('\n');
      } else {
        translated = await OnDeviceTranslator.translate(
          this.ocrText,
          this.detectedLangIso,
          this.targetLangIso,
        );
      }
      this.translatedText = translated;
      this.loading = false;
      this.resultVisible = true;
      this.ocrHeaderVisible = true;
      this.showTranslated = true;
      this.bottomBarVisible = true;
      this.readyForTargetChange = true;
      this.ocrExpanded = false;
    } catch (e) {
      this.loading = false;
      this.toastOcrError(e);
      if (this.ocrText.trim().length > 0) {
        this.resultVisible = true;
        this.ocrHeaderVisible = true;
        this.bottomBarVisible = true;
        this.readyForTargetChange = true;
      } else {
        router.back();
      }
    }
  }

  private async runTranslateOnly(): Promise<void> {
    if (!this.readyForTargetChange || this.ocrText.trim().length === 0) {
      return;
    }
    this.readyForTargetChange = false;
    this.showTranslated = false;
    this.loading = true;
    this.statusText = '正在翻译…';
    try {
      let translated = '';
      if (this.useLineMode && this.layoutLines.length > 0) {
        const outs = await OnDeviceTranslator.translateLines(
          this.layoutLines,
          this.detectedLangIso,
          this.targetLangIso,
        );
        translated = outs.join('\n');
      } else {
        translated = await OnDeviceTranslator.translate(
          this.ocrText,
          this.detectedLangIso,
          this.targetLangIso,
        );
      }
      this.translatedText = translated;
      this.showTranslated = true;
    } catch (e) {
      promptAction.showToast({
        message: (e as Error).message ?? '翻译失败',
        duration: 2500,
      });
    } finally {
      this.loading = false;
      this.readyForTargetChange = true;
    }
  }

  private onTargetPicked(opt: TranslateLanguageOption): void {
    this.targetPickerVisible = false;
    if (opt.isoCode === this.targetLangIso) {
      return;
    }
    this.targetLangIso = opt.isoCode;
    this.updateTargetLabel();
    this.runTranslateOnly();
  }

  @Builder
  TopNavBar() {
    Row() {
      SymbolHeaderButton({
        symbol: $r('sys.symbol.chevron_left'),
        iconSize: 24,
        onAction: () => {
          if (this.photoExpanded) {
            this.collapsePhotoExpand();
          } else {
            router.back();
          }
        }
      })
      Text($r('app.string.camera_result_title'))
        .fontSize(18)
        .fontColor($r('app.color.ui_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Blank().width(48)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 8 })
  }

  @Builder
  LangPill(label: string, clickable: boolean, onTap: () => void) {
    Text(label)
      .fontSize(15)
      .fontColor($r('app.color.ui_text_primary'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .padding({ left: 12, right: 12, top: 14, bottom: 14 })
      .backgroundColor($r('app.color.ui_ime_lang_pill'))
      .border({
        width: 1,
        color: $r('app.color.ui_ime_lang_pill_stroke')
      })
      .borderRadius(14)
      .opacity(clickable ? 1 : 0.85)
      .onClick(() => {
        if (clickable) {
          onTap();
        }
      })
  }

  @Builder
  PhotoPreviewCard() {
    Column() {
      Image(this.photoUri)
        .width('100%')
        .height(PHOTO_PREVIEW_H)
        .objectFit(ImageFit.Cover)
        .onAreaChange((_old, area) => {
          this.thumbWidth = area.width as number;
          this.thumbHeight = area.height as number;
          if (area.globalPosition !== undefined) {
            this.thumbLeft = area.globalPosition.x as number;
            this.thumbTop = area.globalPosition.y as number;
          }
        })
            .onClick(() => {
              if (!this.photoViewerAnimating) {
                this.expandPhotoExpand();
              }
            })
    }
    .width('100%')
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .backgroundColor($r('app.color.ui_camera_card_bg'))
  }

  @Builder
  ResultCard() {
    Column() {
      Stack() {
        if (this.resultVisible) {
              Scroll() {
                Column() {
                  Row() {
                    Text($r('app.string.camera_section_recognize'))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.ui_text_primary'))
                    if (this.ocrHeaderVisible) {
                      Text(this.ocrMetaSummary)
                        .fontSize(13)
                        .fontColor($r('app.color.ui_input_hint'))
                        .layoutWeight(1)
                        .textAlign(TextAlign.End)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ left: 10 })
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(18)
                        .fontColor([$r('app.color.ui_input_hint')])
                        .rotate({ angle: this.ocrExpanded ? 90 : 0 })
                        .margin({ left: 6 })
                    }
                  }
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                  .onClick(() => {
                    if (this.ocrText.trim().length === 0) {
                      return;
                    }
                    this.ocrExpanded = !this.ocrExpanded;
                  })

                  if (this.ocrExpanded && this.ocrHeaderVisible) {
                    Text(this.ocrText)
                      .fontSize(13)
                      .fontColor($r('app.color.ui_input_hint'))
                      .lineHeight(20)
                      .width('100%')
                      .margin({ top: 8 })
                  }

                  if (this.showTranslated) {
                    Text($r('app.string.camera_section_translation'))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.ui_text_primary'))
                      .margin({ top: 18 })
                      .width('100%')
                    Text(this.translatedText)
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.ui_result_translated_green'))
                      .lineHeight(24)
                      .width('100%')
                      .margin({ top: 8 })
                  }
                }
                .width('100%')
                .padding({ left: 18, right: 18, top: 16, bottom: 18 })
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Auto)
            }

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color('#FF26A69A')
            Text(this.statusText)
              .fontSize(15)
              .fontColor($r('app.color.ui_text_primary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.ui_camera_card_bg'))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .backgroundColor($r('app.color.ui_camera_card_bg'))
  }

  build() {
    Stack() {
      Column() {
        this.TopNavBar()

        // 与 Android layout_marginHorizontal=16dp 一致：用父级 padding 保证真机左右留白
        Column({ space: 12 }) {
          this.PhotoPreviewCard()
          this.ResultCard()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: PAGE_H_MARGIN, right: PAGE_H_MARGIN })
        .constraintSize({ minHeight: 0 })

        if (this.bottomBarVisible) {
          Row() {
            Column() {
              this.LangPill(this.sourceLangLabel, false, () => {
              })
            }
            .layoutWeight(1)
            .margin({ left: 4 })

            Blank().width(48)

            Column() {
              this.LangPill(this.targetLangLabel, true, () => {
                if (this.readyForTargetChange) {
                  this.targetPickerVisible = true;
                }
              })
            }
            .layoutWeight(1)
            .margin({ right: 4 })
          }
          .width('100%')
          .padding({
            left: 14,
            right: 14,
            top: 14,
            bottom: 16 + this.navBarBottomInsetVp
          })
          .backgroundColor($r('app.color.ui_camera_page_bg'))
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarTopInsetVp })
      .backgroundColor($r('app.color.ui_camera_page_bg'))
      .onAreaChange((_o, area) => {
        this.screenWidth = area.width as number;
        this.screenHeight = area.height as number;
      })

      if (this.photoExpanded || this.photoExpandProgress > 0 || this.photoViewerAnimating) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#CC000000')
            .opacity(this.photoExpandProgress * 0.55)
            .onClick(() => {
              if (!this.photoViewerAnimating) {
                this.collapsePhotoExpand();
              }
            })

          this.ExpandedPhotoLayer()

          Row() {
            SymbolHeaderButton({
              symbol: $r('sys.symbol.chevron_left'),
              iconSize: 24,
              onAction: () => {
                this.collapsePhotoExpand();
              }
            })
            Blank()
          }
          .width('100%')
          .padding({
            left: 4,
            right: 4,
            top: this.statusBarTopInsetVp + 4
          })
          .zIndex(10)
          .opacity(this.photoExpandProgress > 0.15 ? 1 : this.photoExpandProgress / 0.15)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
      }

      if (this.targetPickerVisible) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor($r('app.color.ui_scrim'))
            .onClick(() => {
              this.targetPickerVisible = false;
            })
          Column() {
            Text($r('app.string.pick_target_language'))
              .fontSize(16)
              .fontColor($r('app.color.ui_text_primary'))
              .width('100%')
              .padding({ top: 16, bottom: 12 })
              .textAlign(TextAlign.Center)
            List() {
              ForEach(TranslateLanguages.getCameraTargetChoices(), (item: TranslateLanguageOption) => {
                ListItem() {
                  Text(item.label)
                    .fontSize(16)
                    .fontColor($r('app.color.ui_text_primary'))
                    .width('100%')
                    .padding({ top: 14, bottom: 14 })
                    .textAlign(TextAlign.Center)
                }
                .onClick(() => {
                  this.onTargetPicked(item);
                })
              }, (item: TranslateLanguageOption) => item.nllbCode)
            }
            .width('100%')
            .height(320)
          }
          .width('100%')
          .backgroundColor($r('app.color.ui_dialog_bg'))
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ui_camera_page_bg'))
  }
}
