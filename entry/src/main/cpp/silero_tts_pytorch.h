#pragma once

#include <cstdint>
#include <string>
#include <vector>

/** Silero torch.package / JIT 合成（fr/de/es/ru 及无 Sherpa 时的 en） */
bool SileroPytorchSynthesize(const std::string &langIso,
                             const std::string &text,
                             const std::string &modelRoot,
                             std::vector<int16_t> &pcmOut,
                             int &sampleRateOut,
                             std::string &errOut);
