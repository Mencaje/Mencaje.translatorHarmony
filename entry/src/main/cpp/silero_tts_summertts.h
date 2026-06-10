#ifndef SILERO_TTS_SUMMERTTS_H
#define SILERO_TTS_SUMMERTTS_H

#include <cstdint>
#include <string>
#include <vector>

bool SummerTtsIsAvailable();
/** 显式释放 SummerTTS 缓存（正常语种切换不再调用，避免 jieba 析构竞态）。 */
void SummerTtsReleaseCachedEngine();
bool SummerTtsIsZhModelPresent(const std::string &modelRoot);
bool SummerTtsSynthesizeZh(const std::string &text,
                           const std::string &modelRoot,
                           std::vector<int16_t> &pcmOut,
                           int &sampleRateOut,
                           std::string &errOut);

#endif
