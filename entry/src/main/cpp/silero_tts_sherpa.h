#pragma once

#include <cstdint>
#include <string>
#include <vector>

/** Offline TTS via sherpa-onnx (Piper/VITS): en/fr/de/es/ru without PyTorch Mobile. */
bool SherpaInferenceIsAvailable();

bool SherpaInferenceIsModelPresent(const std::string &modelRoot, const std::string &langIso);

bool SherpaInferenceSynthesize(const std::string &langIso,
                               const std::string &text,
                               const std::string &modelRoot,
                               std::vector<int16_t> &pcmOut,
                               int &sampleRateOut,
                               std::string &errOut);
