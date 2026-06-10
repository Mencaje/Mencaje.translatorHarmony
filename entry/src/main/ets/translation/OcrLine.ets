/** 单行 OCR（带框，用于阅读顺序，对齐 Android OcrLine） */
export class OcrLine {
  text: string = '';
  top: number = 0;
  left: number = 0;
  bottom: number = 0;
  right: number = 0;

  constructor(text: string, top: number, left: number, bottom: number, right: number) {
    this.text = text;
    this.top = top;
    this.left = left;
    this.bottom = bottom;
    this.right = right;
  }

  get centerY(): number {
    return Math.floor((this.top + this.bottom) / 2);
  }

  get centerX(): number {
    return Math.floor((this.left + this.right) / 2);
  }
}

export class OcrPage {
  fullText: string = '';
  lines: OcrLine[] = [];

  constructor(fullText: string, lines: OcrLine[]) {
    this.fullText = fullText;
    this.lines = lines;
  }
}
