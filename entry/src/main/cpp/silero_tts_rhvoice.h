#pragma once

#include <string>
#include <vector>

bool RhvoiceIsAvailable();
/** 释放缓存的 RHVoice 引擎（跨后端切换时调用）。 */
void RhvoiceReleaseCachedEngine();
bool RhvoiceIsLangSupported(const std::string &langIso);
bool RhvoiceIsModelPresent(const std::string &langIso, const std::string &modelRoot);
bool RhvoiceSynthesize(const std::string &langIso,
                       const std::string &text,
                       const std::string &modelRoot,
                       std::vector<int16_t> &pcmOut,
                       int &sampleRateOut,
                       std::string &errOut);
