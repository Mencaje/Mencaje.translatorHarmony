import { OcrLine } from './OcrLine';

/**
 * 根据 OCR 行框竖直间距插入空行，近似还原照片中的分段（对齐 Android OcrLayoutStructure）。
 */
export class OcrLayoutStructure {
  static insertParagraphBlanks(sortedLines: OcrLine[]): string[] {
    if (sortedLines.length === 0) {
      return [];
    }
    const heights: number[] = [];
    for (let i = 0; i < sortedLines.length; i++) {
      heights.push(Math.max(1, sortedLines[i].bottom - sortedLines[i].top));
    }
    heights.sort((a, b) => a - b);
    const medianH = heights[Math.floor(heights.length / 2)];
    const threshold = Math.max(12, medianH * 1.28);
    const out: string[] = [];
    let prevBottom = -2147483648;
    let hasPrev = false;
    for (let i = 0; i < sortedLines.length; i++) {
      const line = sortedLines[i];
      const t = line.text.trim();
      if (t.length === 0) {
        continue;
      }
      if (hasPrev) {
        const gap = line.top - prevBottom;
        if (gap > threshold) {
          out.push('');
        }
      }
      out.push(t);
      prevBottom = line.bottom;
      hasPrev = true;
    }
    return out;
  }
}
