#pragma once

#include <cstdint>
#include <string>
#include <vector>

/** 递增后使进行中的合成在完成后丢弃结果（与 ArkTS speakEpoch 配合）。 */
uint64_t SileroInferenceBumpGeneration();

uint64_t SileroInferenceCurrentGeneration();

bool SileroInferenceIsCancelled(uint64_t generationToken);

/** 统一离线 TTS 推理入口（SummerTTS / piper-plus）。generationToken 由排队方捕获。 */
bool SileroInferenceSynthesize(uint64_t generationToken,
                               const std::string &langIso,
                               const std::string &text,
                               const std::string &modelRoot,
                               std::vector<int16_t> &pcmOut,
                               int &sampleRateOut,
                               std::string &errOut);

bool SileroInferenceIsLangModelPresent(const std::string &langIso, const std::string &modelRoot);

bool SileroInferenceIsAvailable();

bool SileroInferenceUsesSherpaOnnx();
bool SileroInferenceUsesPytorchMobile();
bool SileroInferenceUsesSummerTts();
bool SileroInferenceUsesPiperPlus();
bool SileroInferenceUsesRhvoice();

std::string SileroInferenceBuildInfo();
