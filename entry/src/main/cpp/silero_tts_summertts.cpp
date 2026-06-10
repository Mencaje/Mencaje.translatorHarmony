/**
 * SummerTTS (MIT) — 中文离线朗读，16 kHz int16 PCM。
 */

#include "silero_tts_summertts.h"

#ifdef SILERO_USE_SUMMERTTS

#include "SynthesizerTrn.h"
#include "utils.h"

#include <sys/stat.h>

#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr int kSampleRate = 16000;
/** single_speaker_fast.bin 约 76MB；与 ArkTS SileroModelPaths.SUMMER_ZH_MIN_BYTES 对齐 */
constexpr int64_t kMinModelBytes = 75LL * 1024 * 1024;
constexpr float kLengthScale = 1.0f;
constexpr int32_t kSpeakerId = 0;
constexpr const char *kZhModelFileName = "single_speaker_fast.bin";

std::mutex gSummerMutex;
float *gModelFloats = nullptr;
int32_t gModelByteSize = 0;
SynthesizerTrn *gSynth = nullptr;
std::string gLoadedModelPath;

std::string JoinPath(const std::string &root, const std::string &name)
{
    if (root.empty()) {
        return name;
    }
    if (root.back() == '/') {
        return root + name;
    }
    return root + "/" + name;
}

std::string ZhModelPath(const std::string &modelRoot)
{
    return JoinPath(modelRoot, kZhModelFileName);
}

bool FileLargeEnough(const std::string &path)
{
    if (path.empty()) {
        return false;
    }
    struct stat st {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return S_ISREG(st.st_mode) && st.st_size >= kMinModelBytes;
}

/** 折叠重复 '/'，避免同一路径因字符串差异触发无谓的引擎销毁/重建。 */
std::string NormalizeModelPath(const std::string &path)
{
    if (path.empty()) {
        return path;
    }
    std::string out;
    out.reserve(path.size());
    for (size_t i = 0; i < path.size(); ++i) {
        const char ch = path[i];
        if (ch == '/' && !out.empty() && out.back() == '/') {
            continue;
        }
        out.push_back(ch);
    }
    return out;
}

void ReleaseSummerEngine()
{
    SynthesizerTrn *toDelete = gSynth;
    gSynth = nullptr;
    delete toDelete;
    if (gModelFloats != nullptr) {
        tts_free_data(gModelFloats);
        gModelFloats = nullptr;
    }
    gModelByteSize = 0;
    gLoadedModelPath.clear();
}

bool EnsureSummerEngine(const std::string &modelPath, std::string &errOut)
{
    const std::string normalizedPath = NormalizeModelPath(modelPath);
    if (gSynth != nullptr && gLoadedModelPath == normalizedPath) {
        if (gSynth->isValid()) {
            return true;
        }
        ReleaseSummerEngine();
    } else if (gSynth != nullptr) {
        ReleaseSummerEngine();
    }

    struct stat modelSt {};
    if (!FileLargeEnough(modelPath) || stat(modelPath.c_str(), &modelSt) != 0) {
        errOut = "Chinese SummerTTS model missing or incomplete: " + modelPath;
        return false;
    }

    std::vector<char> pathBuf(modelPath.begin(), modelPath.end());
    pathBuf.push_back('\0');
    const int32_t modelSize = ttsLoadModel(pathBuf.data(), &gModelFloats);
    if (modelSize <= 0 || gModelFloats == nullptr) {
        errOut = "Failed to load SummerTTS model: " + modelPath;
        ReleaseSummerEngine();
        return false;
    }
    if (static_cast<int64_t>(modelSize) < kMinModelBytes ||
        static_cast<int64_t>(modelSize) > modelSt.st_size) {
        errOut = "SummerTTS model corrupt or truncated: " + modelPath;
        ReleaseSummerEngine();
        return false;
    }

    gModelByteSize = modelSize;
    SynthesizerTrn *synth = nullptr;
    try {
        synth = new SynthesizerTrn(gModelFloats, gModelByteSize);
    } catch (...) {
        synth = nullptr;
    }
    if (synth == nullptr || !synth->isValid()) {
        errOut = "SummerTTS SynthesizerTrn init failed";
        delete synth;
        ReleaseSummerEngine();
        return false;
    }
    gSynth = synth;
    gLoadedModelPath = normalizedPath;
    return true;
}

} // namespace

void SummerTtsReleaseCachedEngine()
{
#ifdef SILERO_USE_SUMMERTTS
    std::lock_guard<std::mutex> lock(gSummerMutex);
    ReleaseSummerEngine();
#endif
}

bool SummerTtsIsAvailable()
{
    return true;
}

bool SummerTtsIsZhModelPresent(const std::string &modelRoot)
{
    return FileLargeEnough(ZhModelPath(modelRoot));
}

bool SummerTtsSynthesizeZh(const std::string &text,
                           const std::string &modelRoot,
                           std::vector<int16_t> &pcmOut,
                           int &sampleRateOut,
                           std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
    if (text.empty()) {
        errOut = "empty text";
        return false;
    }

    const std::string modelPath = ZhModelPath(modelRoot);
    std::lock_guard<std::mutex> lock(gSummerMutex);
    if (!EnsureSummerEngine(modelPath, errOut)) {
        return false;
    }
    if (gSynth == nullptr) {
        errOut = "SummerTTS engine not initialized";
        return false;
    }

    int32_t sampleCount = 0;
    int16_t *wav = nullptr;
    try {
        wav = gSynth->infer(text, kSpeakerId, kLengthScale, sampleCount);
    } catch (...) {
        errOut = "SummerTTS infer failed";
        return false;
    }
    if (wav == nullptr || sampleCount <= 0) {
        errOut = "SummerTTS produced no audio";
        if (wav != nullptr) {
            tts_free_data(wav);
        }
        return false;
    }

    pcmOut.assign(wav, wav + sampleCount);
    tts_free_data(wav);
    sampleRateOut = kSampleRate;
    return true;
}

#else

void SummerTtsReleaseCachedEngine()
{
}

bool SummerTtsIsAvailable()
{
    return false;
}

bool SummerTtsIsZhModelPresent(const std::string &)
{
    return false;
}

bool SummerTtsSynthesizeZh(const std::string &,
                           const std::string &,
                           std::vector<int16_t> &pcmOut,
                           int &sampleRateOut,
                           std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
    errOut = "SummerTTS not compiled into libsilero_tts_napi";
    return false;
}

#endif
