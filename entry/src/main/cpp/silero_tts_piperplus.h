#ifndef SILERO_TTS_PIPERPLUS_H
#define SILERO_TTS_PIPERPLUS_H

#include <cstdint>
#include <string>
#include <vector>

bool PiperPlusIsAvailable();
/** 释放缓存的 piper-plus 引擎（跨后端切换时调用）。 */
void PiperPlusReleaseCachedEngine();
bool PiperPlusIsJaModelPresent(const std::string &modelRoot);
bool PiperPlusIsGenericModelPresent(const std::string &langIso, const std::string &modelRoot);
bool PiperPlusSynthesizeJa(const std::string &text,
                           const std::string &modelRoot,
                           std::vector<int16_t> &pcmOut,
                           int &sampleRateOut,
                           std::string &errOut);
bool PiperPlusSynthesizeGeneric(const std::string &langIso,
                                const std::string &text,
                                const std::string &modelRoot,
                                std::vector<int16_t> &pcmOut,
                                int &sampleRateOut,
                                std::string &errOut);

#endif
