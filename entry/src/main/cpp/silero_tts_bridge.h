#pragma once

#include <cstdint>
#include <string>
#include <vector>

/** Silero TTS NAPI 桥（链接 LibTorch/ONNX 后在本机合成 PCM） */
bool SileroTtsIsLinked();

std::string SileroTtsBuildInfo();

bool SileroTtsUsesSummerTts();
bool SileroTtsUsesPiperPlus();
bool SileroTtsUsesRhvoice();

/** 检测 modelRoot 下某语种模型文件是否存在且非空 */
bool SileroTtsIsLangModelPresent(const std::string &modelRoot, const std::string &langIso);

/** 检测 modelRoot 下是否至少有一个 Silero 支持语种模型 */
bool SileroTtsIsAnyModelPresent(const std::string &modelRoot);

/** 取消进行中的合成（递增世代号，排队中的任务完成后丢弃 PCM）。 */
void SileroTtsCancelSynthesis();

/** 将 text 合成为 16-bit PCM；失败时 errOut 非空 */
bool SileroTtsSynthesize(uint64_t generationToken,
                         const std::string &langIso,
                         const std::string &text,
                         const std::string &modelRoot,
                         std::vector<int16_t> &pcmOut,
                         int &sampleRateOut,
                         std::string &errOut);
